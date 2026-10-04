import Foundation
import Testing

struct SettingsStoreTests {
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

private final class PersistenceWarnings: @unchecked Sendable {
  private let lock = NSLock()
  private var messages: [String] = []
  func add(_ message: String) { lock.withLock { messages.append(message) } }
  var count: Int { lock.withLock { messages.count } }
}
