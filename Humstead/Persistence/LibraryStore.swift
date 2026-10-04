import AVFoundation
import CryptoKit
import Foundation

struct InstalledCollection: Codable, Sendable {
  let collection: DownloadCatalog.Collection
  let assets: [DownloadCatalog.Asset]
}

struct LibrarySnapshot: Sendable {
  var records: [InstalledCollection] = []
  var unavailable: Set<String> = []
  var warning: String?
  var readOnly = false
}

final class AudioFileLease: @unchecked Sendable {
  let url: URL
  private let release: @Sendable () -> Void
  init(url: URL, release: @escaping @Sendable () -> Void = {}) {
    self.url = url
    self.release = release
  }
  deinit { release() }
}

final class LibraryStore: @unchecked Sendable {
  let directory: URL
  private let bundled: Catalog
  private let bundle: Bundle
  private let queue = DispatchQueue(label: "com.mateusnroll.humstead.library")
  private var state = LibrarySnapshot()
  private var leases: [String: Int] = [:]
  private var loaded = false
  private var cacheReadOnly = false

  init(directory: URL, bundled: Catalog, bundle: Bundle) {
    self.directory = directory
    self.bundled = bundled
    self.bundle = bundle
  }
  private var manifest: URL { directory.appendingPathComponent("library.json") }
  private var audio: URL { directory.appendingPathComponent("Audio") }
  var staging: URL { directory.appendingPathComponent("Staging") }

  func load() async -> LibrarySnapshot {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        if !loaded {
          read()
          loaded = true
        }
        continuation.resume(returning: state)
      }
    }
  }
  func snapshot() async -> LibrarySnapshot {
    await withCheckedContinuation { continuation in
      queue.async { [self] in continuation.resume(returning: state) }
    }
  }
  private func read() {
    do {
      try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: staging.path) {
        try FileManager.default.removeItem(at: staging)
      }
      try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
      guard FileManager.default.fileExists(atPath: manifest.path) else {
        collectGarbage()
        return
      }
      let size = try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 2_000_000 else {
        state.readOnly = true
        state.warning =
          "This library exceeds the supported size. Its original file is unchanged and download changes are disabled."
        return
      }
      let data = try Data(contentsOf: manifest)
      struct Header: Decodable { let schemaVersion: Int }
      if let header = try? JSONDecoder().decode(Header.self, from: data), header.schemaVersion > 1 {
        state.readOnly = true
        state.warning =
          "This library was saved by a newer Humstead. Downloads and removal are disabled."
        return
      }
      let catalog = try DownloadCatalog.decode(data, bundled: bundled)
      state.records = catalog.collections.map { collection in
        InstalledCollection(
          collection: collection,
          assets: catalog.assets.filter { collection.assetIDs.contains($0.id) })
      }
      for asset in catalog.assets {
        do { _ = try verifiedLocation(asset) } catch { state.unavailable.insert(asset.id) }
      }
      if !state.unavailable.isEmpty {
        state.warning =
          "Some downloaded audio is missing or damaged. Download its collection again to repair it."
      }
      collectGarbage()
    } catch {
      if FileManager.default.fileExists(atPath: manifest.path) {
        do {
          try FileManager.default.copyItem(
            at: manifest,
            to: directory.appendingPathComponent("library-recovery-\(UUID().uuidString).json"))
          state.warning =
            "An unreadable library was preserved in a recovery file. Bundled audio is available."
        } catch {
          state.readOnly = true
          state.warning =
            "The library could not be recovered safely. Download changes are disabled."
        }
      } else {
        state.readOnly = true
        state.warning = "The download library could not be opened. Bundled audio is available."
      }
    }
  }

  private func combined(_ records: [InstalledCollection]) throws -> DownloadCatalog {
    var assets: [String: DownloadCatalog.Asset] = [:]
    for record in records {
      guard Set(record.collection.assetIDs) == Set(record.assets.map(\.id)) else {
        throw DownloadError.invalidCatalog
      }
      for asset in record.assets {
        if let existing = assets[asset.id], existing != asset {
          throw DownloadError.invalidCatalog
        }
        assets[asset.id] = asset
      }
    }
    let catalog = DownloadCatalog(
      schemaVersion: 1, catalogVersion: 1,
      collections: records.map(\.collection), assets: assets.values.sorted { $0.id < $1.id })
    try catalog.validate(bundled: bundled)
    return catalog
  }

  func install(
    _ record: InstalledCollection, staged: [String: URL], gate: DownloadOperationGate? = nil
  ) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      queue.async { [self] in
        do {
          guard loaded, !state.readOnly else { throw DownloadError.libraryReadOnly }
          try gate?.check()
          let next = state.records.filter { $0.collection.id != record.collection.id } + [record]
          let catalog = try combined(next)
          let data = try JSONEncoder().encode(catalog)
          guard data.count <= 2_000_000 else { throw DownloadError.invalidCatalog }
          let acceptedHashes = Set(record.assets.map(\.sha256))
          guard Set(staged.keys).isSubset(of: acceptedHashes) else {
            throw DownloadError.invalidCatalog
          }
          for asset in record.assets {
            if let partial = staged[asset.sha256] {
              guard
                partial.standardizedFileURL.path.hasPrefix(staging.standardizedFileURL.path + "/")
              else {
                throw DownloadError.invalidCatalog
              }
              try Self.verify(partial, asset: asset)
            } else {
              _ = try verifiedLocation(asset)
            }
          }
          for asset in record.assets {
            guard let partial = staged[asset.sha256] else { continue }
            let target = blob(asset)
            if FileManager.default.fileExists(atPath: target.path) {
              if (try? Self.verify(target, asset: asset)) != nil { continue }
              guard leases[target.lastPathComponent, default: 0] == 0 else {
                throw DownloadError.fileInUse
              }
              try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: partial, to: target)
          }
          let commit = {
            try data.write(to: self.manifest, options: .atomic)
            self.state.records = next
            self.state.unavailable.formIntersection(catalog.assets.map(\.id))
            self.state.unavailable.subtract(
              catalog.assets.filter { acceptedHashes.contains($0.sha256) }.map(\.id))
            self.state.warning =
              self.state.unavailable.isEmpty
              ? nil
              : "Some downloaded audio is missing or damaged. Download its collection again to repair it."
          }
          if let gate { try gate.commit(commit) } else { try commit() }
          collectGarbage()
          continuation.resume()
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  func remove(_ id: String) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      queue.async { [self] in
        do {
          guard loaded, !state.readOnly else { throw DownloadError.libraryReadOnly }
          let next = state.records.filter { $0.collection.id != id }
          let data = try JSONEncoder().encode(combined(next))
          try data.write(to: manifest, options: .atomic)
          state.records = next
          state.unavailable.formIntersection(next.flatMap { $0.assets.map(\.id) })
          collectGarbage()
          continuation.resume()
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  func acquire(_ asset: Catalog.Asset) throws -> AudioFileLease {
    if let original = bundled.asset(asset.id), original.sha256 == asset.sha256 {
      return AudioFileLease(url: try Catalog.verifiedURL(for: original, bundle: bundle))
    }
    return try queue.sync {
      guard
        let installed = state.records.flatMap(\.assets).first(where: {
          $0.id == asset.id && $0.sha256 == asset.sha256
        })
      else {
        throw DownloadError.unavailableAudio
      }
      let url = try verifiedLocation(installed)
      if installed.bundledEquivalent != nil { return AudioFileLease(url: url) }
      let key = url.lastPathComponent
      leases[key, default: 0] += 1
      return AudioFileLease(url: url) { [weak self] in
        guard let self else { return }
        self.queue.async {
          self.leases[key, default: 0] -= 1
          if self.leases[key] == 0 { self.leases.removeValue(forKey: key) }
          self.collectGarbage()
        }
      }
    }
  }

  func missingAssets(_ assets: [DownloadCatalog.Asset]) async -> [DownloadCatalog.Asset] {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        var seen: Set<String> = []
        continuation.resume(
          returning: assets.filter { asset in
            seen.insert(asset.sha256).inserted && (try? verifiedLocation(asset)) == nil
          })
      }
    }
  }

  private func blob(_ asset: DownloadCatalog.Asset) -> URL {
    audio.appendingPathComponent((asset.path as NSString).lastPathComponent)
  }
  private func verifiedLocation(_ asset: DownloadCatalog.Asset) throws -> URL {
    if let equivalent = asset.bundledEquivalent, let original = bundled.asset(equivalent) {
      return try Catalog.verifiedURL(for: original, bundle: bundle)
    }
    let url = blob(asset)
    try Self.verify(url, asset: asset)
    return url
  }
  static func verify(_ url: URL, asset: DownloadCatalog.Asset) throws {
    let values = try url.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      values.fileSize == asset.byteLength
    else { throw DownloadError.invalidAudio("size or file type") }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var hash = SHA256()
    while let data = try file.read(upToCount: 65536), !data.isEmpty { hash.update(data: data) }
    guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == asset.sha256 else {
      throw DownloadError.invalidAudio("hash")
    }
    let audioFile = try AVAudioFile(forReading: url)
    let format = withExtendedLifetime(audioFile) {
      audioFile.fileFormat.streamDescription.pointee
    }
    guard
      asset.codec == "aac-lc"
        ? format.mFormatID == kAudioFormatMPEG4AAC
        : format.mFormatID == kAudioFormatLinearPCM && format.mBitsPerChannel == 16
          && format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
          && format.mFormatFlags & (kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsFloat) == 0
    else { throw DownloadError.invalidAudio("codec") }
  }

  private func collectGarbage() {
    guard !state.readOnly else { return }
    let retained = Set(state.records.flatMap(\.assets).map { blob($0).lastPathComponent })
    do {
      for url in try FileManager.default.contentsOfDirectory(
        at: audio, includingPropertiesForKeys: nil)
      where !retained.contains(url.lastPathComponent)
        && leases[url.lastPathComponent, default: 0] == 0
      {
        try FileManager.default.removeItem(at: url)
      }
    } catch {
      state.warning =
        "Some unused download files could not be removed. Try again after restarting Humstead."
    }
  }
}

struct CatalogCache: Codable, Sendable {
  var schemaVersion = 1
  var data: Data?
  var etag: String?
  var attemptedAt: Date?
}

extension LibraryStore {
  func loadCache() async -> (CatalogCache, String?) {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        let url = directory.appendingPathComponent("catalog.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
          continuation.resume(returning: (CatalogCache(), nil))
          return
        }
        do {
          let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
          guard size <= 3_000_000 else {
            cacheReadOnly = true
            continuation.resume(
              returning: (
                CatalogCache(),
                "The catalog cache exceeds the supported size. Its original file is unchanged and online changes are disabled."
              ))
            return
          }
          let bytes = try Data(contentsOf: url)
          struct Header: Decodable { let schemaVersion: Int }
          if try JSONDecoder().decode(Header.self, from: bytes).schemaVersion > 1 {
            cacheReadOnly = true
            continuation.resume(
              returning: (
                CatalogCache(),
                "The catalog cache belongs to a newer Humstead. Online changes are disabled."
              ))
            return
          }
          let cache = try JSONDecoder().decode(CatalogCache.self, from: bytes)
          guard cache.schemaVersion == 1 else { throw DownloadError.invalidCatalog }
          if let data = cache.data { _ = try DownloadCatalog.decode(data, bundled: bundled) }
          continuation.resume(returning: (cache, nil))
        } catch {
          do {
            try FileManager.default.copyItem(
              at: url,
              to: directory.appendingPathComponent("catalog-recovery-\(UUID().uuidString).json"))
          } catch { cacheReadOnly = true }
          continuation.resume(
            returning: (
              CatalogCache(), "The catalog cache could not be read. Local listening is available."
            ))
        }
      }
    }
  }

  func saveCache(_ cache: CatalogCache) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      queue.async { [self] in
        do {
          guard !cacheReadOnly, !state.readOnly else { throw DownloadError.libraryReadOnly }
          let data = try JSONEncoder().encode(cache)
          guard data.count <= 3_000_000 else { throw DownloadError.invalidCatalog }
          try data.write(to: directory.appendingPathComponent("catalog.json"), options: .atomic)
          continuation.resume()
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
}
