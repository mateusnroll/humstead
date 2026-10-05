import Foundation
import Testing

struct UsageReporterTests {
  @Test func consentAndConcurrentPreferences() async throws {
    let context = try UsageContext()
    defer { context.remove() }
    var preferences = MixSettings()
    await context.reporter.load(await context.store.load())
    await context.reporter.record(.timer, token: context.reporter.token)
    #expect(!FileManager.default.fileExists(atPath: context.file.path))
    preferences.musicVolume = 0.2
    context.store.save(preferences)
    let enabled = await context.reporter.setConsent(true, revision: context.reporter.close())
    #expect(enabled.enabled)
    preferences.musicVolume = 0.8
    context.store.save(preferences)
    #expect(context.store.flush(timeout: 1))
    let saved = await SettingsStore(directory: context.directory).load()
    #expect(saved.settings.analyticsChoice == "enabled")
    #expect(saved.settings.musicVolume == 0.8)
    let stale = context.reporter.token
    let disabled = await context.reporter.setConsent(false, revision: context.reporter.close())
    #expect(!disabled.enabled)
    await context.reporter.record(.timer, token: stale)
    #expect(
      await SettingsStore(directory: context.directory).load().settings.analyticsChoice
        == "disabled")
    #expect(!FileManager.default.fileExists(atPath: context.file.path))
    #expect(context.sink.payloads.isEmpty)
  }

  @Test func semanticOutcomeBuckets() async throws {
    let context = try UsageContext()
    defer { context.remove() }
    await context.enable()
    for _ in 0..<20 {
      await context.reporter.record(.failedDownload, token: context.reporter.token)
    }
    for outcome in [UsageReporter.Outcome.ambience(only: true), .timer, .menuBar, .download] {
      await context.reporter.record(outcome, token: context.reporter.token)
    }
    let state = try context.object()
    #expect(state["downloadFailures"] as? Int == 6)
    for key in ["usedAmbience", "usedAmbienceOnly", "usedTimer", "usedMenuBar", "usedDownloads"] {
      #expect(state[key] as? Bool == true)
    }
    #expect(
      Set(state.keys)
        == Set([
          "schemaVersion", "windowStart", "usedAmbience", "usedAmbienceOnly", "usedTimer",
          "usedMenuBar", "usedDownloads", "downloadFailures",
        ]))
  }

  @Test func boundedStateAndRecovery() async throws {
    for bytes in [
      Data("{broken".utf8), Data(repeating: 65, count: 4097), Data("{\"schemaVersion\":99}".utf8),
    ] {
      let context = try UsageContext()
      defer { context.remove() }
      try bytes.write(to: context.file)
      var loaded = SettingsStore.Loaded()
      loaded.settings.analyticsChoice = "enabled"
      await context.reporter.load(loaded)
      #expect(context.reporter.token == nil)
      #expect(try Data(contentsOf: context.file) == bytes)
      #expect(
        try FileManager.default.contentsOfDirectory(atPath: context.directory.path).filter {
          $0.contains("recovery")
        }.isEmpty)
      _ = await context.reporter.setConsent(false, revision: context.reporter.close())
      #expect(!FileManager.default.fileExists(atPath: context.file.path))
    }
  }

  @Test func consumeOnceAndDisableRace() async throws {
    let pause = UsagePause()
    let context = try UsageContext(beforeSend: { await pause.wait() })
    defer { context.remove() }
    await context.enable()
    let old = context.reporter.token
    await context.reporter.record(.timer, token: old)
    context.clock.advance(604799)
    await context.reporter.check()
    #expect(context.sink.payloads.isEmpty)
    context.clock.advance(1)
    let check = Task { await context.reporter.check() }
    for _ in 0..<100 where !(await pause.entered) { try await Task.sleep(for: .milliseconds(10)) }
    #expect(await pause.entered)
    #expect(!FileManager.default.fileExists(atPath: context.file.path))
    _ = await context.reporter.setConsent(false, revision: context.reporter.close())
    await pause.release()
    await check.value
    #expect(context.sink.payloads.isEmpty)
    await context.enable()
    await context.reporter.record(.timer, token: old)
    #expect(!FileManager.default.fileExists(atPath: context.file.path))
  }

  @Test func closedPayloadAndFreshIDs() async throws {
    let context = try UsageContext()
    defer { context.remove() }
    await context.enable()
    for _ in 0..<2 {
      await context.reporter.record(.timer, token: context.reporter.token)
      context.clock.advance(604800)
      await context.reporter.check()
      try await Task.sleep(for: .milliseconds(20))
      await context.reporter.check()
    }
    #expect(context.sink.payloads.count == 2)
    var ids: Set<String> = []
    for data in context.sink.payloads {
      let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
      #expect(Set(body.keys) == Set(["api_key", "event", "distinct_id", "properties"]))
      #expect(body["event"] as? String == "humstead_usage_summary")
      let id = try #require(body["distinct_id"] as? String)
      #expect(UUID(uuidString: id) != nil)
      ids.insert(id)
      let props = try #require(body["properties"] as? [String: Any])
      #expect(
        Set(props.keys)
          == Set([
            "schemaVersion", "appVersion", "usedAmbience", "usedAmbienceOnly", "usedTimer",
            "usedMenuBar", "usedDownloads", "downloadFailures", "$process_person_profile",
            "$geoip_disable",
          ]))
      #expect(props["appVersion"] as? String == "0.1")
      #expect(props["downloadFailures"] as? String == "zero")
      #expect(props["$process_person_profile"] as? Bool == false)
      #expect(props["$geoip_disable"] as? Bool == true)
    }
    #expect(ids.count == 2)
    for file in try FileManager.default.contentsOfDirectory(
      at: context.directory, includingPropertiesForKeys: nil)
    {
      let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
      #expect(ids.allSatisfy { !text.contains($0) })
    }
  }

  @Test func delayedWriteAndRapidConsent() async throws {
    let pause = UsageWritePause()
    let context = try UsageContext(beforeWrite: pause.wait)
    defer {
      pause.release()
      context.remove()
    }
    await context.enable()
    let old = context.reporter.token
    let write = Task { await context.reporter.record(.timer, token: old) }
    for _ in 0..<100 where !pause.entered { try await Task.sleep(for: .milliseconds(10)) }
    #expect(pause.entered)
    let disabled = context.reporter.close()
    let disable = Task { await context.reporter.setConsent(false, revision: disabled) }
    let enabled = context.reporter.close()
    let enable = Task { await context.reporter.setConsent(true, revision: enabled) }
    pause.release()
    await write.value
    _ = await disable.value
    #expect(await enable.value.enabled)
    #expect(!FileManager.default.fileExists(atPath: context.file.path))
    await context.reporter.record(.download, token: old)
    #expect(!FileManager.default.fileExists(atPath: context.file.path))
    #expect(
      await SettingsStore(directory: context.directory).load().settings.analyticsChoice == "enabled"
    )
  }

  @Test func failedConsumptionAndConsentRemainOff() async throws {
    let context = try UsageContext()
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: context.directory.path)
      context.remove()
    }
    await context.enable()
    await context.reporter.record(.timer, token: context.reporter.token)
    let original = try Data(contentsOf: context.file)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: context.directory.path)
    context.clock.advance(604800)
    await context.reporter.check()
    #expect(context.reporter.token == nil)
    #expect(context.sink.payloads.isEmpty)
    #expect(try Data(contentsOf: context.file) == original)
    let result = await context.reporter.setConsent(false, revision: context.reporter.close())
    #expect(!result.enabled && result.warning != nil)
    #expect(
      await SettingsStore(directory: context.directory).load().settings.analyticsChoice == "enabled"
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: context.directory.path)
    _ = await context.reporter.setConsent(false, revision: context.reporter.close())
    #expect(!FileManager.default.fileExists(atPath: context.file.path))
    #expect(
      await SettingsStore(directory: context.directory).load().settings.analyticsChoice
        == "disabled")
  }

  @Test func futureWindowAndRestartDoNotReplay() async throws {
    let context = try UsageContext()
    defer { context.remove() }
    await context.enable()
    await context.reporter.record(.timer, token: context.reporter.token)
    var object = try context.object()
    object["windowStart"] = context.clock.wall() + 86400
    try JSONSerialization.data(withJSONObject: object).write(to: context.file)
    context.reporter.close()
    let restarted = UsageReporter(
      directory: context.directory, store: context.store,
      configuration: UsageConfiguration(
        endpoint: URL(string: "http://127.0.0.1:38477/i/v0/e")!, token: "humstead-local-test",
        version: "0.1"),
      clock: UsageClock(wall: context.clock.wall, elapsed: context.clock.elapsed),
      transport: context.sink)
    await restarted.load(await context.store.load())
    context.clock.advance(604799)
    await restarted.check()
    #expect(context.sink.payloads.isEmpty)
    context.clock.advance(1)
    await restarted.check()
    #expect(context.sink.payloads.count == 1)
    restarted.close()
    let final = UsageReporter(
      directory: context.directory, store: context.store,
      configuration: UsageConfiguration(
        endpoint: URL(string: "http://127.0.0.1:38477/i/v0/e")!, token: "humstead-local-test",
        version: "0.1"),
      clock: UsageClock(wall: context.clock.wall, elapsed: context.clock.elapsed),
      transport: context.sink)
    await final.load(await context.store.load())
    context.clock.advance(604800 * 10)
    await final.check()
    #expect(context.sink.payloads.count == 1)
    final.close()
  }

  @Test func closedStartupCannotRestoreConsent() async throws {
    let context = try UsageContext()
    defer { context.remove() }
    var settings = SettingsStore.Loaded()
    settings.settings.analyticsChoice = "enabled"
    context.reporter.close()
    await context.reporter.load(settings)
    #expect(context.reporter.token == nil)
    await context.reporter.record(.timer, token: context.reporter.token)
    #expect(!FileManager.default.fileExists(atPath: context.file.path))
    #expect(context.sink.payloads.isEmpty)
  }

  @Test func productionConfigurationGate() {
    #expect(
      UsageConfiguration.resolve(build: "Release", bundleID: "com.mateusnroll.humstead") == nil)
    #expect(
      UsageConfiguration.resolve(
        build: "Debug", bundleID: "com.mateusnroll.humstead", token: "phc_test", attested: true)
        == nil)
    #expect(
      UsageConfiguration.resolve(
        build: "Release", bundleID: "org.fork.humstead", token: "phc_test", attested: true) == nil)
    #expect(
      UsageConfiguration.resolve(
        build: "Release", bundleID: "com.mateusnroll.humstead", token: "phc_test", attested: true)?
        .endpoint.absoluteString == "https://eu.i.posthog.com/i/v0/e")
    #expect(
      UsageConfiguration.resolve(
        build: "Testing", bundleID: "com.mateusnroll.humstead.testing",
        testingURL: URL(string: "https://eu.i.posthog.com")) == nil)
    #expect(
      UsageConfiguration.resolve(
        build: "Testing", bundleID: "com.mateusnroll.humstead.testing",
        testingURL: URL(string: "http://127.0.0.1:38477")) != nil)
    #expect(
      UsageConfiguration.resolve(
        build: "Release", bundleID: "com.mateusnroll.humstead", token: "phc_test", attested: true,
        version: "0.1.personal") == nil)
  }
}

private struct UsageContext {
  let directory: URL
  let store: SettingsStore
  let reporter: UsageReporter
  let sink = UsageSink()
  let clock = TestUsageClock()
  var file: URL { directory.appendingPathComponent("usage.json") }
  init(
    beforeSend: @escaping @Sendable () async -> Void = {},
    beforeWrite: @escaping @Sendable () -> Void = {}
  ) throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "usage-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    store = SettingsStore(directory: directory)
    reporter = UsageReporter(
      directory: directory, store: store,
      configuration: UsageConfiguration(
        endpoint: URL(string: "http://127.0.0.1:38477/i/v0/e")!, token: "humstead-local-test",
        version: "0.1"),
      clock: UsageClock(wall: clock.wall, elapsed: clock.elapsed), transport: sink,
      beforeSend: beforeSend, beforeWrite: beforeWrite)
  }
  func enable() async {
    await reporter.load(await store.load())
    _ = await reporter.setConsent(true, revision: reporter.close())
  }
  func object() throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
  }
  func remove() {
    _ = reporter.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
private final class TestUsageClock: @unchecked Sendable {
  let lock = NSLock()
  var value = 1_800_000_000.0
  func wall() -> Double { lock.withLock { value } }
  func elapsed() -> Double { wall() }
  func advance(_ seconds: Double) { lock.withLock { value += seconds } }
}
private final class UsageSink: UsageSending, @unchecked Sendable {
  let lock = NSLock()
  private var data: [Data] = []
  var payloads: [Data] { lock.withLock { data } }
  func send(_ data: Data, completion: @escaping @Sendable () -> Void) {
    lock.withLock { self.data.append(data) }
    completion()
  }
  func cancel() {}
}
private actor UsagePause {
  var entered = false
  var continuation: CheckedContinuation<Void, Never>?
  func wait() async {
    entered = true
    await withCheckedContinuation { continuation = $0 }
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
}

private final class UsageWritePause: @unchecked Sendable {
  private let lock = NSLock()
  private let semaphore = DispatchSemaphore(value: 0)
  private var value = false
  var entered: Bool { lock.withLock { value } }
  func wait() {
    lock.withLock { value = true }
    if semaphore.wait(timeout: .now() + 5) != .success {
      Issue.record("Delayed write was not released.")
    }
  }
  func release() { semaphore.signal() }
}
