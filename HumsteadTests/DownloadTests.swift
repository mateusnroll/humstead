import Foundation
import Testing

struct DownloadTests {
  @Test func controlCoalescesAndRecoversAfterWake() async throws {
    let server = try await DownloadFixture.start()
    defer { server.stop() }
    let local = try LibraryFixture()
    defer { try? FileManager.default.removeItem(at: local.directory) }
    let library = local.store()
    _ = await library.load()
    let clock = DownloadTestClock()
    let coordinator = DownloadCoordinator(
      origin: try DownloadOrigin(server.origin, testing: true),
      library: library, bundled: local.bundled, now: { clock.now })
    await coordinator.load()
    try await server.configure(["control_delay": 0.2])
    async let first: Void = coordinator.checkControl()
    async let second: Void = coordinator.checkControl()
    _ = try await (first, second)
    #expect(try await server.requests("/control/v1.json").count == 1)
    clock.advance(51)
    let stale = Task { try await coordinator.checkControl() }
    for _ in 0..<100 {
      if try await server.requests("/control/v1.json").count == 2 { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    await coordinator.wake()
    let fresh = Task { try await coordinator.checkControl() }
    await #expect(throws: (any Error).self) { try await stale.value }
    try await coordinator.checkControl()
    try await fresh.value
    #expect(try await server.requests("/control/v1.json").count == 3)
    try await coordinator.checkControl()
    #expect(try await server.requests("/control/v1.json").count == 3)
  }

  @Test func catalogRefreshAdmission() async throws {
    let server = try await DownloadFixture.start()
    defer { server.stop() }
    let local = try LibraryFixture()
    defer { try? FileManager.default.removeItem(at: local.directory) }
    let library = local.store()
    _ = await library.load()
    let clock = DownloadTestClock()
    let coordinator = DownloadCoordinator(
      origin: try DownloadOrigin(server.origin, testing: true), library: library,
      bundled: local.bundled, now: { clock.now }, date: { clock.date })
    await coordinator.load()
    await coordinator.refresh(manual: false)
    #expect(await coordinator.snapshot().catalog?.catalogVersion == 1)
    await coordinator.refresh(manual: false)
    await coordinator.refresh(manual: true)
    var requests = try await server.requests("/catalog/v1.json")
    #expect(requests.count == 1)
    clock.advance(61)
    await coordinator.refresh(manual: true)
    requests = try await server.requests("/catalog/v1.json")
    #expect(requests.count == 2)
    #expect(requests.last?["if_none_match"] as? String == "\"fixture-1\"")
    clock.advance(61)
    try await server.configure(["large_catalog": true])
    await coordinator.refresh(manual: true)
    #expect(await coordinator.snapshot().catalog?.catalogVersion == 1)
    #expect(await coordinator.snapshot().message != nil)
    let restarted = DownloadCoordinator(
      origin: try DownloadOrigin(server.origin, testing: true), library: library,
      bundled: local.bundled, now: { clock.now }, date: { clock.date })
    await restarted.load()
    await restarted.refresh(manual: false)
    #expect(await restarted.snapshot().catalog?.catalogVersion == 1)
    #expect(try await server.requests("/catalog/v1.json").count == 3)
  }

  @Test func controlShutdownLease() async throws {
    let server = try await DownloadFixture.start()
    defer { server.stop() }
    let local = try LibraryFixture()
    defer { try? FileManager.default.removeItem(at: local.directory) }
    let library = local.store()
    _ = await library.load()
    let clock = DownloadTestClock()
    let coordinator = DownloadCoordinator(
      origin: try DownloadOrigin(server.origin, testing: true), library: library,
      bundled: local.bundled, now: { clock.now }, date: { clock.date })
    await coordinator.load()
    await coordinator.refresh(manual: true)
    let plan = try await coordinator.plan("extra-music")
    try await server.configure(["chunk_delay": 0.2])
    let task = Task { try await coordinator.install(plan) }
    for _ in 0..<100 {
      if try await !server.requests("/" + plan.missing[0].path).isEmpty { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    try await server.configure(["enabled": false, "revision": 2])
    clock.advance(51)
    let shutdownStart = ContinuousClock.now
    await #expect(throws: (any Error).self) { try await task.value }
    #expect(shutdownStart.duration(to: .now) < .seconds(14))
    #expect(await library.snapshot().records.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: library.staging.path).isEmpty)
    let requests = try await server.requests("/" + plan.missing[0].path).count
    clock.advance(61)
    await #expect(throws: (any Error).self) { try await coordinator.install(plan) }
    #expect(try await server.requests("/" + plan.missing[0].path).count == requests)
    try await server.configure(["enabled": true, "malformed_control": true])
    await #expect(throws: (any Error).self) { try await coordinator.checkControl() }
  }

  @Test func twoFileRetryAndAtomicInstall() async throws {
    let server = try await DownloadFixture.start()
    defer { server.stop() }
    let local = try LibraryFixture()
    defer { try? FileManager.default.removeItem(at: local.directory) }
    let library = local.store()
    _ = await library.load()
    let origin = try DownloadOrigin(server.origin, testing: true)
    let coordinator = DownloadCoordinator(origin: origin, library: library, bundled: local.bundled)
    await coordinator.load()
    await coordinator.refresh(manual: true)
    let first = try await coordinator.plan("extra-music")
    try await server.configure(["version": 2])
    let response = try await HTTPTransfer.request(
      origin: origin, path: "catalog/v1.json", limit: 2_000_000)
    let second = try #require(
      DownloadCatalog.decode(response.data).assets.first { $0.kind == "music" })
    let assets = first.record.assets + [second]
    let record = InstalledCollection(
      collection: DownloadCatalog.Collection(
        id: "two-songs", kind: "music", version: 1, label: "Two songs", stationID: "mellow",
        assetIDs: assets.map(\.id), totalBytes: assets.reduce(0) { $0 + $1.byteLength }),
      assets: assets)
    try await server.configure(["fail_audio": 2, "chunk_delay": 0.02])
    try await coordinator.install(DownloadPlan(record: record, missing: assets))
    #expect(await library.snapshot().records.count == 1)
    #expect(await library.missingAssets(assets).isEmpty)
    var count = 0
    for asset in assets { count += try await server.requests("/" + asset.path).count }
    #expect(count == 4)
    let journal = try await server.journal()
    #expect(journal["max_active_audio"] as? Int == 2)
    #expect(try FileManager.default.contentsOfDirectory(atPath: library.staging.path).isEmpty)
  }

  @Test func retryLimitPreservesInstalledVersion() async throws {
    let server = try await DownloadFixture.start()
    defer { server.stop() }
    let local = try LibraryFixture()
    defer { try? FileManager.default.removeItem(at: local.directory) }
    let library = local.store()
    _ = await library.load()
    try await library.install(local.record, staged: local.staged())
    let origin = try DownloadOrigin(server.origin, testing: true)
    try await server.configure(["version": 2, "fail_audio": 3])
    let coordinator = DownloadCoordinator(origin: origin, library: library, bundled: local.bundled)
    await coordinator.load()
    await coordinator.refresh(manual: true)
    let plan = try await coordinator.plan("extra-music")
    await #expect(throws: (any Error).self) { try await coordinator.install(plan) }
    let requests = try await server.requests("/" + plan.missing[0].path)
    #expect(requests.count == 3)
    let times = requests.compactMap { $0["monotonic"] as? Double }
    #expect(times.count == 3)
    if times.count == 3 {
      #expect(times[1] - times[0] >= 1.9)
      #expect(times[2] - times[1] >= 7.9)
    }
    #expect(await library.snapshot().records.first?.collection.version == 1)
    #expect(try library.acquire(local.asset.metadata).url.isFileURL)
    #expect(try FileManager.default.contentsOfDirectory(atPath: library.staging.path).isEmpty)
  }

  @Test func transferBoundsAndCancellation() async throws {
    let server = try await DownloadFixture.start()
    defer { server.stop() }
    let origin = try DownloadOrigin(server.origin, testing: true)
    let catalogResponse = try await HTTPTransfer.request(
      origin: origin, path: "catalog/v1.json", limit: 2_000_000)
    let catalog = try DownloadCatalog.decode(catalogResponse.data)
    let asset = try #require(catalog.assets.first)
    let destination = server.directory.appendingPathComponent("transfer")
    let result = try await HTTPTransfer.request(
      origin: origin, path: asset.path, limit: asset.byteLength, destination: destination)
    #expect(result.file == destination)
    try LibraryStore.verify(destination, asset: asset)
    try FileManager.default.removeItem(at: destination)
    await #expect(throws: (any Error).self) {
      _ = try await HTTPTransfer.request(
        origin: origin, path: asset.path, limit: asset.byteLength - 1, destination: destination)
    }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    await #expect(throws: (any Error).self) {
      _ = try await HTTPTransfer.request(
        origin: origin, path: asset.path, limit: asset.byteLength, destination: destination,
        capacity: { _ in 0 })
    }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    try await server.configure(["chunk_delay": 0.1])
    let slow = Task {
      try await HTTPTransfer.request(
        origin: origin, path: asset.path, limit: asset.byteLength, destination: destination)
    }
    try await Task.sleep(for: .milliseconds(250))
    slow.cancel()
    await #expect(throws: (any Error).self) { try await slow.value }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    try await server.configure(["corrupt_audio": true, "chunk_delay": 0])
    _ = try await HTTPTransfer.request(
      origin: origin, path: asset.path, limit: asset.byteLength, destination: destination)
    #expect(throws: (any Error).self) { try LibraryStore.verify(destination, asset: asset) }
    try FileManager.default.removeItem(at: destination)
    try await server.configure(["redirect_audio": true])
    await #expect(throws: (any Error).self) {
      _ = try await HTTPTransfer.request(
        origin: origin, path: asset.path,
        limit: asset.byteLength, destination: destination)
    }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    try await server.configure(["large_control": true])
    await #expect(throws: (any Error).self) {
      _ = try await HTTPTransfer.request(
        origin: origin, path: "control/v1.json", limit: 16_384, timeout: 5)
    }

  }
}

final class DownloadFixture: @unchecked Sendable {
  let process: Process
  let directory: URL
  let origin: URL
  private let terminated: DispatchSemaphore
  private init(process: Process, directory: URL, origin: URL, terminated: DispatchSemaphore) {
    self.terminated = terminated
    self.process = process
    self.directory = directory
    self.origin = origin
  }
  static func start() async throws -> DownloadFixture {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let ready = directory.appendingPathComponent("ready.json")
    let process = Process()
    let terminated = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in terminated.signal() }
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [
      root.appendingPathComponent("scripts/download-fixture.py").path,
      "--root", root.path, "--ready", ready.path,
    ]
    try process.run()
    do {
      for _ in 0..<100 {
        if let data = try? Data(contentsOf: ready),
          let object = try? JSONDecoder().decode([String: String].self, from: data),
          let value = object["origin"], let origin = URL(string: value)
        {
          return DownloadFixture(
            process: process, directory: directory, origin: origin, terminated: terminated)
        }
        try await Task.sleep(for: .milliseconds(50))
      }
      throw TransferError.invalidResponse
    } catch {
      process.terminate()
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }
  func configure(_ values: [String: any Sendable]) async throws {
    var request = URLRequest(url: origin.appendingPathComponent("__configure"))
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: values)
    let (_, response) = try await URLSession.shared.data(for: request)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
  }
  func journal() async throws -> [String: Any] {
    let (data, _) = try await URLSession.shared.data(
      from: origin.appendingPathComponent("__journal"))
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  func requests(_ path: String) async throws -> [[String: Any]] {
    let (data, _) = try await URLSession.shared.data(
      from: origin.appendingPathComponent("__journal"))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return (object["requests"] as? [[String: Any]] ?? []).filter { $0["path"] as? String == path }
  }
  func stop() {
    if process.isRunning { process.terminate() }
    guard terminated.wait(timeout: .now() + 5) == .success else {
      Issue.record("The local fixture did not finish shutting down within five seconds.")
      return
    }
    try? FileManager.default.removeItem(at: directory)
  }
}

final class DownloadTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0.0
  var now: Double { lock.withLock { value } }
  var date: Date { Date(timeIntervalSince1970: 1_800_000_000 + now) }
  func advance(_ seconds: Double) { lock.withLock { value += seconds } }
}
