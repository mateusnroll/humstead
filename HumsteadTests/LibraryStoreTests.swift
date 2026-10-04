import AVFoundation
import CryptoKit
import Foundation
import Testing

private final class LibraryTestBundle: NSObject {}

struct LibraryStoreTests {
  @MainActor @Test func layerLimitFeedbackSurvivesPlaybackUpdates() async throws {
    let fixture = try LibraryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let forest = try #require(fixture.bundled.asset("forest"))
    let assets = (0..<17).map { index in
      DownloadCatalog.Asset(
        id: "layer-\(index)", kind: "ambience", sha256: forest.sha256,
        byteLength: forest.byteLength, codec: forest.codec, duration: forest.duration,
        path: "audio/\(forest.sha256).caf", title: "Forest \(index)", creator: forest.creator,
        originalSourceURL: forest.sourceURL, creatorProfileURL: forest.profileURL,
        license: "CC0", licenseVersion: "1.0", licenseURL: forest.licenseURL,
        attribution: forest.attribution, modification: forest.modification, bundledEquivalent: nil)
    }
    let library = fixture.store()
    _ = await library.load()
    let staged = library.staging.appendingPathComponent("forest.caf")
    try FileManager.default.copyItem(
      at: Catalog.verifiedURL(for: forest, bundle: fixture.bundle), to: staged)
    let record = InstalledCollection(
      collection: DownloadCatalog.Collection(
        id: "many-layers", kind: "ambience", version: 1, label: "Many layers", stationID: nil,
        assetIDs: assets.map(\.id), totalBytes: assets.reduce(0) { $0 + $1.byteLength }),
      assets: assets)
    try await library.install(record, staged: [forest.sha256: staged])
    let model = PlayerModel(directory: fixture.directory, bundle: fixture.bundle)
    defer { model.stop() }
    for _ in 0..<100 where model.state.catalog == nil {
      try await Task.sleep(for: .milliseconds(20))
    }
    try #require(model.state.catalog != nil)
    for asset in assets.prefix(16) { model.setLayer(asset.id, enabled: true, level: 0) }
    model.setLayer(assets[16].id, enabled: true, level: 0)
    let message = try #require(model.layerMessage)
    let sequence = model.state.sequence
    model.setVolume(0.13)
    for _ in 0..<100 where model.state.sequence <= sequence {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(model.state.sequence > sequence)
    #expect(model.layerMessage == message)
    #expect(model.settings.mix.values.filter { $0.enabled }.count == 16)
    model.resetAmbience()
    #expect(model.layerMessage == nil)
  }

  @Test func unreadableManifestPreservesAudio() async throws {
    let fixture = try LibraryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let store = fixture.store()
    _ = await store.load()
    try await store.install(fixture.record, staged: fixture.staged())
    let blob = try store.acquire(fixture.asset.metadata).url
    let manifest = fixture.directory.appendingPathComponent("library.json")
    let broken = Data("{broken".utf8)
    try broken.write(to: manifest)
    let recovered = fixture.store()
    #expect(await recovered.load().readOnly)
    await #expect(throws: (any Error).self) { try await recovered.remove("unknown") }
    #expect(try Data(contentsOf: manifest) == broken)
    #expect(FileManager.default.fileExists(atPath: blob.path))
  }

  @MainActor @Test func stopCancelsPendingRemoval() async throws {
    let fixture = try LibraryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let store = fixture.store()
    _ = await store.load()
    try await store.install(fixture.record, staged: fixture.staged())
    let manifest = fixture.directory.appendingPathComponent("library.json")
    let original = try Data(contentsOf: manifest)
    let model = PlayerModel(directory: fixture.directory, bundle: fixture.bundle)
    for _ in 0..<100 where model.state.catalog == nil {
      try await Task.sleep(for: .milliseconds(20))
    }
    try #require(model.state.catalog != nil)
    model.removeCollection(fixture.record.collection.id)
    model.stop()
    for _ in 0..<100 where model.removing {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(!model.removing)
    #expect(try Data(contentsOf: manifest) == original)
    #expect(model.downloadError == nil)
  }

  @Test func rejectsMislabeledPCM() throws {
    let fixture = try LibraryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let forest = try #require(fixture.bundled.asset("forest"))
    var bytes = try Data(contentsOf: Catalog.verifiedURL(for: forest, bundle: fixture.bundle))
    try #require(String(data: bytes[8..<12], encoding: .ascii) == "desc")
    // This invalid fixture changes the CAF descriptor only, never the shipped recording.
    bytes[35] &= ~2
    let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    let url = fixture.directory.appendingPathComponent("invalid-endianness.caf")
    try bytes.write(to: url)
    let file = try AVAudioFile(forReading: url)
    try #require(
      file.fileFormat.streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsBigEndian != 0)
    let asset = DownloadCatalog.Asset(
      id: "invalid-forest", kind: "ambience", sha256: hash,
      byteLength: bytes.count, codec: "pcm_s16le", duration: forest.duration,
      path: "audio/\(hash).caf", title: forest.title, creator: forest.creator,
      originalSourceURL: forest.sourceURL, creatorProfileURL: forest.profileURL,
      license: "CC0", licenseVersion: "1.0", licenseURL: forest.licenseURL,
      attribution: forest.attribution,
      modification: "Malformed format fixture; never played or shipped.", bundledEquivalent: nil)
    #expect(throws: (any Error).self) { try LibraryStore.verify(url, asset: asset) }
  }

  @Test func sharedRepairRetainsOtherWarnings() async throws {
    let first = try LibraryFixture()
    defer { try? FileManager.default.removeItem(at: first.directory) }
    let alias = try LibraryFixture(
      assetID: "alias-snow", collectionID: "alias-pack", directory: first.directory)
    let other = try LibraryFixture(
      originalID: "2-hour-delay", assetID: "extra-delay", collectionID: "other-pack",
      directory: first.directory)
    let library = first.store()
    _ = await library.load()
    try await library.install(first.record, staged: first.staged())
    try await library.install(alias.record, staged: [:])
    try await library.install(other.record, staged: other.staged())
    let snowURL = try library.acquire(first.asset.metadata).url
    let otherURL = try library.acquire(other.asset.metadata).url
    try Data("corrupt".utf8).write(to: snowURL)
    try Data("corrupt".utf8).write(to: otherURL)
    let restarted = first.store()
    #expect(await restarted.load().unavailable.count == 3)
    try await restarted.install(first.record, staged: first.staged())
    let repaired = await restarted.snapshot()
    #expect(!repaired.unavailable.contains(alias.asset.id))
    #expect(repaired.unavailable.contains(other.asset.id))
    #expect(repaired.warning != nil)
  }

  @Test func installedPlaybackAndMixRecall() async throws {
    var settings = MixSettings()
    settings.stationSettings["mellow"] = MixSettings.Station(
      selectedPresetID: "rainy-window",
      presetMixes: ["rainy-window": ["extra-forest": AmbienceLevel(enabled: true, level: 0.17)]])
    let available = Set(MixSettings.soundIDs + ["extra-forest"])
    let restored = try settings.validated(availableSounds: available)
    #expect(restored.mix["extra-forest"]?.enabled == true)
    #expect(restored.mix["extra-forest"]?.level == 0.17)
    let removed = try restored.validated()
    #expect(removed.mix["extra-forest"]?.enabled == false)
    #expect(removed.mix["extra-forest"]?.level == 0.17)
    #expect(try removed.validated(availableSounds: available).mix["extra-forest"]?.enabled == false)
    var bounded = MixSettings()
    let optional = Set((1...17).map { "optional-\($0)" })
    for id in optional.sorted().prefix(16) {
      let accepted = bounded.setLayer(id, enabled: true, level: 0.2, availableSounds: optional)
      #expect(accepted)
    }
    let seventeenth = try #require(optional.sorted().last)
    let acceptedLast = bounded.setLayer(
      seventeenth, enabled: true, level: 0.2, availableSounds: optional)
    #expect(!acceptedLast)
    #expect(bounded.mix.values.filter { $0.enabled }.count == 16)

    let fixture = try LibraryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let library = fixture.store()
    _ = await library.load()
    try await library.install(fixture.record, staged: fixture.staged())
    let snapshot = await library.snapshot()
    let merged = fixture.bundled.merging(snapshot)
    #expect(
      merged.stations.first { $0.id == "mellow" }?.assetIDs.contains(fixture.asset.id) == true)
    let isolated = Catalog(
      schemaVersion: 1,
      stations: [Catalog.Station(id: "mellow", title: "Mellow", assetIDs: [fixture.asset.id])],
      assets: merged.assets)
    var quiet = MixSettings()
    quiet.musicVolume = 0.03
    let controller = AudioController(
      bundle: fixture.bundle, settings: quiet,
      catalog: isolated, library: library, publish: { _ in })
    defer { controller.stop() }
    _ = await controller.snapshot()
    controller.setPlaying(true, requestID: 1)
    let playing = await controller.snapshot()
    #expect(playing.trackID == fixture.asset.id)
    #expect(playing.isPlaying)
    await controller.refreshCatalog(fixture.bundled, bundled: fixture.bundled, mix: [:])
    let switched = await controller.snapshot()
    #expect(switched.playbackRequested)
    #expect(switched.isPlaying)
    #expect(fixture.bundled.asset(switched.trackID) != nil)
    try await library.remove(fixture.record.collection.id)
    #expect(await library.snapshot().records.isEmpty)

  }

  @Test func atomicInstallAndRecovery() async throws {
    let fixture = try LibraryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let library = fixture.store()
    #expect(await library.load().records.isEmpty)
    try await library.install(fixture.record, staged: fixture.staged())
    #expect(await library.snapshot().records.count == 1)
    let manifest = fixture.directory.appendingPathComponent("library.json")
    let previous = try Data(contentsOf: manifest)
    let broken = fixture.directory.appendingPathComponent("Staging/broken")
    try Data("wrong".utf8).write(to: broken)
    await #expect(throws: (any Error).self) {
      try await library.install(fixture.record, staged: [fixture.asset.sha256: broken])
    }
    #expect(try Data(contentsOf: manifest) == previous)
    let saved = fixture.directory.appendingPathComponent("old-manifest.json")
    try FileManager.default.moveItem(at: manifest, to: saved)
    try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
    await #expect(throws: (any Error).self) {
      try await library.remove(fixture.record.collection.id)
    }
    #expect(await library.snapshot().records.count == 1)
    #expect(try library.acquire(fixture.asset.metadata).url.isFileURL)
    try FileManager.default.removeItem(at: manifest)
    try FileManager.default.moveItem(at: saved, to: manifest)
    #expect(await fixture.store().load().records.count == 1)
    let future = Data("{\"schemaVersion\":99,\"records\":[]}".utf8)
    try future.write(to: manifest)
    let newer = fixture.store()
    #expect(await newer.load().readOnly)
    await #expect(throws: (any Error).self) { try await newer.remove("extra-music") }
    #expect(try Data(contentsOf: manifest) == future)
    let largeFuture = future + Data(repeating: 32, count: 2_000_001)
    try largeFuture.write(to: manifest)
    let oversized = fixture.store()
    #expect(await oversized.load().readOnly)
    await #expect(throws: (any Error).self) { try await oversized.remove("extra-music") }
    #expect(try Data(contentsOf: manifest) == largeFuture)
    try Data("broken".utf8).write(to: manifest)
    #expect(await fixture.store().load().warning != nil)
    let preserved = try FileManager.default.contentsOfDirectory(
      at: fixture.directory, includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("library-recovery-") }
    #expect(preserved.count == 1)
  }

  @Test func leasedRemovalAndSharedBlobs() async throws {
    let fixture = try LibraryFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let library = fixture.store()
    _ = await library.load()
    try await library.install(fixture.record, staged: fixture.staged())
    let shared = InstalledCollection(
      collection: DownloadCatalog.Collection(
        id: "shared-music", kind: "music", version: 1, label: "Shared Mellow",
        stationID: "mellow", assetIDs: [fixture.asset.id], totalBytes: fixture.asset.byteLength),
      assets: [fixture.asset])
    try await library.install(shared, staged: [:])
    var lease: AudioFileLease? = try library.acquire(fixture.asset.metadata)
    let blob = try #require(lease?.url)
    try await library.remove(fixture.record.collection.id)
    #expect(await library.snapshot().records.count == 1)
    #expect(FileManager.default.fileExists(atPath: blob.path))
    try await library.remove(shared.collection.id)
    #expect(await library.snapshot().records.isEmpty)
    #expect(FileManager.default.fileExists(atPath: blob.path))
    lease = nil
    _ = await library.snapshot()
    #expect(!FileManager.default.fileExists(atPath: blob.path))
    #expect(FileManager.default.fileExists(atPath: fixture.source.path))
  }
}

struct LibraryFixture {
  let directory: URL
  let bundle: Bundle
  let bundled: Catalog
  let asset: DownloadCatalog.Asset
  let record: InstalledCollection
  let source: URL

  init(
    originalID: String = "snow-drift", assetID: String = "extra-snow",
    collectionID: String = "extra-music", directory suppliedDirectory: URL? = nil
  ) throws {
    directory =
      suppliedDirectory
      ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    bundle = Bundle(for: LibraryTestBundle.self)
    bundled = try Catalog.load(bundle: bundle)
    let original = try #require(bundled.assets.first { $0.id == originalID })
    source = try Catalog.verifiedURL(for: original, bundle: bundle)
    asset = DownloadCatalog.Asset(
      id: assetID, kind: "music", sha256: original.sha256, byteLength: original.byteLength,
      codec: original.codec, duration: original.duration, path: "audio/\(original.sha256).m4a",
      title: original.title, creator: original.creator, originalSourceURL: original.sourceURL,
      creatorProfileURL: original.profileURL, license: "CC0", licenseVersion: "1.0",
      licenseURL: original.licenseURL, attribution: original.attribution,
      modification: original.modification, bundledEquivalent: nil)
    record = InstalledCollection(
      collection: DownloadCatalog.Collection(
        id: collectionID, kind: "music", version: 1, label: "Extra Mellow", stationID: "mellow",
        assetIDs: [asset.id], totalBytes: asset.byteLength), assets: [asset])
    try FileManager.default.createDirectory(
      at: directory.appendingPathComponent("Staging"), withIntermediateDirectories: true)
  }
  func store() -> LibraryStore {
    LibraryStore(directory: directory, bundled: bundled, bundle: bundle)
  }
  func staged() throws -> [String: URL] {
    let target = directory.appendingPathComponent("Staging/\(UUID().uuidString)")
    try FileManager.default.copyItem(at: source, to: target)
    return [asset.sha256: target]
  }
}
