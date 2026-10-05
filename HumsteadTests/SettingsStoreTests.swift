import Foundation
import Testing

struct SettingsStoreTests {
  @Test func maximumOptionalMixesRemainReadable() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let sounds = Set(
      (0..<2000).map { String(repeating: "s", count: 76) + String(format: "%04d", $0) })
    let layers = Dictionary(
      uniqueKeysWithValues: sounds.map { ($0, AmbienceLevel(enabled: false, level: 0.17)) })
    var settings = MixSettings()
    for station in MixSettings.stationIDs {
      settings.stationSettings[station] = MixSettings.Station(
        selectedPresetID: "forest",
        presetMixes: Dictionary(uniqueKeysWithValues: MixSettings.presets.map { ($0.id, layers) }))
    }
    let store = SettingsStore(directory: directory, availableSounds: sounds)
    _ = await store.load()
    store.save(settings)
    #expect(store.flush(timeout: 1))
    let data = try Data(contentsOf: directory.appendingPathComponent("settings.json"))
    #expect(data.count > 2_000_000)
    let loaded = await SettingsStore(directory: directory, availableSounds: sounds).load()
    #expect(loaded.warning == nil)
    #expect(try loaded.settings == settings.validated(availableSounds: sounds))
  }

  @MainActor @Test func startupEditsPreserveSavedPreferences() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var saved = MixSettings()
    saved.currentStationID = "late-night"
    saved.musicVolume = 0.22
    let file = directory.appendingPathComponent("settings.json")
    try JSONEncoder().encode(saved).write(to: file)
    let model = PlayerModel(directory: directory, bundle: Bundle(for: SettingsTestBundle.self))
    model.setVolume(0.9)
    for _ in 0..<100 where model.state.catalog == nil {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(model.state.catalog != nil)
    #expect(model.settings == saved)
    model.stop()
    let persisted = try JSONDecoder().decode(MixSettings.self, from: Data(contentsOf: file))
    #expect(persisted == saved)
  }

  @Test func atomicRecoveryAndLatestWrite() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SettingsStore(directory: directory)
    #expect(await store.load().settings == MixSettings())
    var settings = MixSettings()
    settings.selectPreset("forest")
    for value in [0.2, 0.4, 0.7] {
      settings.musicVolume = value
      store.save(settings)
    }
    #expect(store.flush(timeout: 1))
    let restored = await SettingsStore(directory: directory).load()
    #expect(restored.settings.musicVolume == 0.7)
    #expect(restored.settings.presetID == "forest")
    let file = directory.appendingPathComponent("settings.json")
    let bad = Data("{broken".utf8)
    try bad.write(to: file)
    let recovery = await SettingsStore(directory: directory).load()
    #expect(recovery.warning != nil)
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    let preserved = try #require(
      files.first { $0.lastPathComponent.hasPrefix("settings-recovery-") })
    #expect(try Data(contentsOf: preserved) == bad)
    let future = Data("{\"schemaVersion\":99,\"unknown\":true}".utf8)
    try future.write(to: file)
    let newer = SettingsStore(directory: directory)
    #expect(await newer.load().readOnly)
    newer.save(settings)
    #expect(newer.flush(timeout: 1))
    #expect(try Data(contentsOf: file) == future)
    try bad.write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    let blocked = await SettingsStore(directory: directory).load()
    #expect(blocked.readOnly && blocked.warning != nil)
    #expect(try Data(contentsOf: file) == bad)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    let valid = try JSONEncoder().encode(settings)
    try valid.write(to: file)
    let warnings = PersistenceWarnings()
    let failedWrite = SettingsStore(directory: directory, warning: warnings.add)
    _ = await failedWrite.load()
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    settings.musicVolume = 0.1
    failedWrite.save(settings)
    #expect(failedWrite.flush(timeout: 1))
    #expect(try Data(contentsOf: file) == valid)
    #expect(warnings.count > 0)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }
}

private final class SettingsTestBundle: NSObject {}

private final class PersistenceWarnings: @unchecked Sendable {
  private let lock = NSLock()
  private var messages: [String] = []
  func add(_ message: String) { lock.withLock { messages.append(message) } }
  var count: Int { lock.withLock { messages.count } }
}
