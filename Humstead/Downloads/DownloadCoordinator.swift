import Foundation

struct DownloadPlan: Sendable {
  let record: InstalledCollection
  let missing: [DownloadCatalog.Asset]
  var missingBytes: Int { missing.reduce(0) { $0 + $1.byteLength } }
}

struct DownloadState: Sendable {
  var sequence: UInt64 = 0
  var catalog: DownloadCatalog?
  var refreshing = false
  var activeID: String?
  var progress = 0
  var total = 0
  var message: String?
}

actor DownloadCoordinator {
  private let origin: DownloadOrigin?
  private let library: LibraryStore
  private let bundled: Catalog
  private let now: @Sendable () -> Double
  private let date: @Sendable () -> Date
  private let publish: @Sendable (DownloadState) -> Void
  private var state = DownloadState()
  private var cache = CatalogCache()
  private var loaded = false
  private var controlTime: Double?
  private var controlTask: Task<Double, any Error>?
  private var controlGeneration = 0
  private var operation: Task<Void, any Error>?
  private var watcher: Task<Void, Never>?
  private var gate: DownloadOperationGate?
  private var operationID: UUID?

  init(
    origin: DownloadOrigin?, library: LibraryStore, bundled: Catalog,
    now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
    date: @escaping @Sendable () -> Date = { Date() },
    publish: @escaping @Sendable (DownloadState) -> Void = { _ in }
  ) {
    self.origin = origin
    self.library = library
    self.bundled = bundled
    self.now = now
    self.date = date
    self.publish = publish
  }
  func load() async {
    guard !loaded else { return }
    loaded = true
    let result = await library.loadCache()
    cache = result.0
    state.message = result.1
    if let data = cache.data { state.catalog = try? DownloadCatalog.decode(data, bundled: bundled) }
    if origin == nil {
      state.message =
        "Online collections are not configured in this build. All local audio is available."
    }
    emit()
  }
  private func emit() {
    state.sequence += 1
    publish(state)
  }
  func snapshot() -> DownloadState { state }

  func refresh(manual: Bool) async {
    guard loaded, let origin, !state.refreshing else { return }
    if let last = cache.attemptedAt, date().timeIntervalSince(last) < (manual ? 60 : 86400) {
      return
    }
    state.refreshing = true
    emit()
    defer {
      state.refreshing = false
      emit()
    }
    do {
      cache.attemptedAt = date()
      try await library.saveCache(cache)
      let response = try await HTTPTransfer.request(
        origin: origin, path: "catalog/v1.json", limit: 2_000_000, etag: cache.etag)
      if response.status == 304 {
        guard state.catalog != nil, cache.data != nil else { throw DownloadError.invalidCatalog }
      } else {
        let catalog = try DownloadCatalog.decode(response.data, bundled: bundled)
        var updated = cache
        updated.data = response.data
        updated.etag = response.etag
        try await library.saveCache(updated)
        cache = updated
        state.catalog = catalog
      }
      state.message = nil
    } catch {
      state.message =
        "Could not check for collections. Local audio and saved listings are available. Try Check for updates again in a minute."
    }
  }

  func plan(_ id: String) async throws -> DownloadPlan {
    guard state.activeID == nil, let catalog = state.catalog,
      let collection = catalog.collections.first(where: { $0.id == id })
    else { throw DownloadError.invalidCatalog }
    let record = InstalledCollection(
      collection: collection,
      assets: catalog.assets.filter { collection.assetIDs.contains($0.id) })
    return DownloadPlan(record: record, missing: await library.missingAssets(record.assets))
  }

  func install(_ plan: DownloadPlan) async throws {
    guard loaded, origin != nil, operationID == nil else { throw DownloadError.invalidCatalog }
    let id = UUID()
    let gate = DownloadOperationGate()
    let directory = library.staging.appendingPathComponent(id.uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    operationID = id
    self.gate = gate
    state.activeID = plan.record.collection.id
    state.progress = 0
    state.total = plan.missingBytes
    state.message = nil
    emit()
    let task = Task { try await self.execute(plan, directory: directory, id: id, gate: gate) }
    operation = task
    watcher = Task {
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        guard self.operationID == id else { return }
        if let age = self.controlTime.map({ self.now() - $0 }), age >= 60 {
          self.cancel()
          return
        }
        if self.controlTime.map({ self.now() - $0 >= 50 }) ?? false {
          do { try await self.checkControl() } catch { return }
        }
      }
    }
    defer {
      watcher?.cancel()
      watcher = nil
      operation = nil
      operationID = nil
      self.gate = nil
      state.activeID = nil
      do { try FileManager.default.removeItem(at: directory) } catch {
        state.message =
          "Some partial downloads could not be removed. Restart Humstead to clean them up."
      }
      emit()
    }
    do {
      try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
        gate.cancel()
      }
      state.progress = state.total
    } catch {
      state.message =
        error is CancellationError
        ? "Download cancelled. Your installed audio is unchanged."
        : "Download stopped. Check your connection, available storage and download availability, then Retry. Your installed audio is unchanged."
      throw error
    }
  }

  private func execute(_ plan: DownloadPlan, directory: URL, id: UUID, gate: DownloadOperationGate)
    async throws
  {
    let missing = await library.missingAssets(plan.record.assets)
    let confirmed = Set(plan.missing.map(\.sha256))
    guard missing.allSatisfy({ confirmed.contains($0.sha256) }) else {
      throw DownloadError.unavailableAudio
    }
    let reservation = DownloadReservation(missing)
    let staged = try await withThrowingTaskGroup(of: (String, URL).self) { group in
      var index = 0
      var files: [String: URL] = [:]
      func add(_ asset: DownloadCatalog.Asset) {
        group.addTask {
          try await self.transfer(
            asset, directory: directory, id: id, gate: gate, reservation: reservation)
        }
      }
      while index < min(2, missing.count) {
        add(missing[index])
        index += 1
      }
      while let (hash, url) = try await group.next() {
        files[hash] = url
        if index < missing.count {
          add(missing[index])
          index += 1
        }
      }
      return files
    }
    try Task.checkCancellation()
    try gate.check()
    try await library.install(plan.record, staged: staged, gate: gate)
  }

  private func transfer(
    _ asset: DownloadCatalog.Asset, directory: URL, id: UUID,
    gate: DownloadOperationGate, reservation: DownloadReservation
  ) async throws -> (String, URL) {
    guard let origin else { throw DownloadError.invalidCatalog }
    for attempt in 0...2 {
      try Task.checkCancellation()
      try gate.check()
      try await checkControl()
      try Task.checkCancellation()
      try gate.check()
      guard controlTime.map({ now() - $0 < 60 }) == true else {
        throw DownloadError.downloadsDisabled
      }
      let file = directory.appendingPathComponent(UUID().uuidString)
      reservation.update(asset.sha256, bytes: 0)
      do {
        _ = try await HTTPTransfer.request(
          origin: origin, path: asset.path, limit: asset.byteLength, destination: file,
          capacity: { url in
            try HTTPTransfer.availableCapacity(url) - reservation.otherRemaining(asset.sha256)
          },
          progress: { bytes in
            reservation.update(asset.sha256, bytes: bytes)
            let received = reservation.received
            Task { await self.progress(received, id: id) }
          })
        try Task.checkCancellation()
        try gate.check()
        try LibraryStore.verify(file, asset: asset)
        return (asset.sha256, file)
      } catch {
        try? FileManager.default.removeItem(at: file)
        guard attempt < 2, Self.transient(error) else { throw error }
        try await Task.sleep(for: .seconds(attempt == 0 ? 2 : 8))
      }
    }
    throw TransferError.invalidResponse
  }
  private func progress(_ bytes: Int, id: UUID) {
    guard operationID == id, bytes > state.progress else { return }
    state.progress = bytes
    emit()
  }
  private static func transient(_ error: any Error) -> Bool {
    if case TransferError.status(let status) = error {
      return status == 429 || (500...599).contains(status)
    }
    guard let error = error as? URLError else { return false }
    return [
      .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
      .cannotFindHost, .dnsLookupFailed,
    ].contains(error.code)
  }
  func cancel() {
    gate?.cancel()
    operation?.cancel()
  }

  func checkControl() async throws {
    if let time = controlTime, now() - time < 50 { return }
    guard let origin else { throw DownloadError.downloadsDisabled }
    let task: Task<Double, any Error>
    if let pending = controlTask {
      task = pending
    } else {
      controlGeneration += 1
      task = Task {
        let response = try await HTTPTransfer.request(
          origin: origin, path: "control/v1.json", limit: 16_384, timeout: 5)
        struct Control: Decodable {
          let downloadsEnabled: Bool
          let revision: Int
        }
        let value = try JSONDecoder().decode(Control.self, from: response.data)
        guard value.downloadsEnabled, value.revision >= 0 else {
          throw DownloadError.downloadsDisabled
        }
        return self.now()
      }
      controlTask = task
    }
    let generation = controlGeneration
    do {
      let receivedAt = try await task.value
      guard generation == controlGeneration, now() - receivedAt < 60 else {
        throw DownloadError.downloadsDisabled
      }
      controlTime = receivedAt
      controlTask = nil
    } catch {
      if generation == controlGeneration {
        controlTime = nil
        controlTask = nil
        cancel()
      }
      throw error
    }
  }

  func wake() {
    controlGeneration += 1
    controlTime = nil
    controlTask?.cancel()
    controlTask = nil
    cancel()
  }
}

final class DownloadOperationGate: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  private var committed = false
  func cancel() { lock.withLock { if !committed { cancelled = true } } }
  func check() throws { try lock.withLock { if cancelled { throw CancellationError() } } }
  func commit(_ body: () throws -> Void) throws {
    try lock.withLock {
      if cancelled { throw CancellationError() }
      try body()
      committed = true
    }
  }
}

private final class DownloadReservation: @unchecked Sendable {
  private let lock = NSLock()
  private let sizes: [String: Int]
  private var progress: [String: Int] = [:]
  init(_ assets: [DownloadCatalog.Asset]) {
    sizes = Dictionary(uniqueKeysWithValues: assets.map { ($0.sha256, $0.byteLength) })
  }
  func update(_ hash: String, bytes: Int) { lock.withLock { progress[hash] = bytes } }
  var received: Int { lock.withLock { progress.values.reduce(0, +) } }
  func otherRemaining(_ hash: String) -> Int64 {
    lock.withLock {
      Int64(
        sizes.reduce(0) {
          $0 + ($1.key == hash ? 0 : max(0, $1.value - progress[$1.key, default: 0]))
        })
    }
  }
}
