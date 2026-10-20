import Foundation

struct UsageConfiguration: Sendable {
  let endpoint: URL
  let token: String
  let version: String
  static func resolve(
    build: String, bundleID: String, token: String = "", attested: Bool = false,
    version: String = "0.1.0", testingURL: URL? = nil
  ) -> UsageConfiguration? {
    let parts = version.split(separator: ".", omittingEmptySubsequences: false)
    guard (2...3).contains(parts.count),
      parts.allSatisfy({
        !$0.isEmpty && $0.count <= 6 && $0.allSatisfy({ $0.isASCII && $0.isNumber })
      })
    else { return nil }
    let releaseVersion = parts.prefix(2).joined(separator: ".")
    if build == "Testing", bundleID == "com.mateusnroll.humstead.testing", let url = testingURL,
      url.scheme == "http", url.host == "127.0.0.1", url.user == nil, url.password == nil,
      url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/"
    {
      return Self(
        endpoint: url.appendingPathComponent("i/v0/e"), token: "humstead-local-test",
        version: releaseVersion)
    }
    guard build == "Release", bundleID == "com.mateusnroll.humstead", attested,
      token.hasPrefix("phc_"), (5...256).contains(token.count),
      token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
    else { return nil }
    return Self(
      endpoint: URL(string: "https://eu.i.posthog.com/i/v0/e")!, token: token,
      version: releaseVersion)
  }
}

protocol UsageSending: Sendable {
  func send(_ data: Data, completion: @escaping @Sendable () -> Void)
  func cancel()
}

struct UsageClock: Sendable {
  var wall: @Sendable () -> Double = { Date().timeIntervalSince1970 }
  var elapsed: @Sendable () -> Double = { monotonic() }
  private static let origin = ContinuousClock.now
  static func monotonic() -> Double {
    let value = origin.duration(to: .now).components
    return Double(value.seconds) + Double(value.attoseconds) / 1e18
  }
}

actor UsageReporter {
  enum Outcome: Sendable {
    case ambience(only: Bool)
    case timer, menuBar, download, failedDownload
  }
  struct Presentation: Sendable {
    var enabled = false
    var warning: String?
    var revision: UInt64 = 0
  }
  private struct Window: Codable {
    var schemaVersion = 1
    var windowStart: Double
    var usedAmbience = false
    var usedAmbienceOnly = false
    var usedTimer = false
    var usedMenuBar = false
    var usedDownloads = false
    var downloadFailures = 0
    static let keys: Set<String> = [
      "schemaVersion", "windowStart", "usedAmbience", "usedAmbienceOnly", "usedTimer",
      "usedMenuBar", "usedDownloads", "downloadFailures",
    ]
  }
  private final class Admission: @unchecked Sendable {
    let lock = NSLock()
    var revision: UInt64 = 0
    var enabled = false
    func current(_ revision: UInt64) -> Bool { lock.withLock { self.revision == revision } }
    func allows(_ token: UInt64?) -> Bool { lock.withLock { enabled && token == revision } }
  }
  private nonisolated let admission = Admission()
  nonisolated var revision: UInt64 { admission.lock.withLock { admission.revision } }
  nonisolated var token: UInt64? {
    admission.lock.withLock { admission.enabled ? admission.revision : nil }
  }
  private let directory: URL
  private let store: SettingsStore
  private let configuration: UsageConfiguration?
  private let clock: UsageClock
  private nonisolated let transport: any UsageSending
  private let beforeSend: @Sendable () async -> Void
  private let beforeWrite: @Sendable () -> Void
  private let publish: @Sendable (Presentation) -> Void
  private var loaded = false
  private var unsafe = false
  private var settingsSafe = false
  private var window: Window?
  private var anchor = 0.0
  private var initialAge = 0.0
  private var activeAttempt: UUID?
  private var file: URL { directory.appendingPathComponent("usage.json") }
  init(
    directory: URL, store: SettingsStore, configuration: UsageConfiguration?,
    clock: UsageClock = UsageClock(),
    transport: any UsageSending, beforeSend: @escaping @Sendable () async -> Void = {},
    beforeWrite: @escaping @Sendable () -> Void = {},
    publish: @escaping @Sendable (Presentation) -> Void = { _ in }
  ) {
    self.directory = directory
    self.store = store
    self.configuration = configuration
    self.clock = clock
    self.transport = transport
    self.beforeSend = beforeSend
    self.beforeWrite = beforeWrite
    self.publish = publish
  }
  @discardableResult nonisolated func close() -> UInt64 {
    let revision = admission.lock.withLock {
      admission.revision += 1
      admission.enabled = false
      return admission.revision
    }
    transport.cancel()
    return revision
  }
  func load(_ settings: SettingsStore.Loaded) async {
    guard !loaded else { return }
    loaded = true
    let revision = admission.lock.withLock { admission.revision }
    settingsSafe = !settings.readOnly && settings.warning == nil
    guard configuration != nil, settingsSafe else { return }
    do {
      if FileManager.default.fileExists(atPath: file.path) {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 4096 else { throw UsageError.invalid }
        let data = try Data(contentsOf: file)
        guard data.count <= 4096,
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          Set(object.keys) == Window.keys
        else { throw UsageError.invalid }
        let value = try JSONDecoder().decode(Window.self, from: data)
        guard value.schemaVersion == 1, value.windowStart.isFinite, value.windowStart >= 0,
          (0...6).contains(value.downloadFailures)
        else { throw UsageError.invalid }
        window = value
        anchor = clock.elapsed()
        initialAge = max(0, clock.wall() - value.windowStart)
        guard anchor.isFinite, initialAge.isFinite else { throw UsageError.invalid }
      }
      if settings.settings.analyticsChoice == "enabled", revision == 0 {
        admission.lock.withLock { if admission.revision == revision { admission.enabled = true } }
        announce(Presentation(enabled: true))
        await check()
      }
    } catch {
      fail(
        "Saved usage data could not be read safely. Reporting is off. Turn sharing off to clear this data."
      )
    }
  }
  func setConsent(_ enabled: Bool, revision: UInt64) async -> Presentation {
    guard admission.current(revision) else { return Presentation() }
    guard settingsSafe, !enabled || (configuration != nil && !unsafe) else {
      return announce(
        Presentation(warning: "Your sharing choice could not be saved. Reporting is off."))
    }
    do { try clear() } catch {
      return fail(
        "Your sharing choice could not be saved. Reporting is off; pending data could not be cleared."
      )
    }
    let saved = await store.setAnalyticsConsent(enabled)
    guard admission.current(revision) else { return Presentation() }
    guard saved else {
      return fail("Your sharing choice could not be saved. Reporting is off for this session.")
    }
    unsafe = false
    admission.lock.withLock { if admission.revision == revision { admission.enabled = enabled } }
    return announce(Presentation(enabled: enabled))
  }
  func record(_ outcome: Outcome, token: UInt64?) async {
    guard admission.allows(token), !unsafe else { return }
    await check()
    guard admission.allows(token), !unsafe else { return }
    if window == nil {
      let wall = clock.wall()
      let elapsed = clock.elapsed()
      guard wall.isFinite, wall >= 0, elapsed.isFinite else {
        _ = fail("Reporting is off because the reporting clock is unavailable.")
        return
      }
      window = Window(windowStart: wall)
      anchor = elapsed
      initialAge = 0
    }
    switch outcome {
    case .ambience(let only):
      window?.usedAmbience = true
      if only { window?.usedAmbienceOnly = true }
    case .timer: window?.usedTimer = true
    case .menuBar: window?.usedMenuBar = true
    case .download: window?.usedDownloads = true
    case .failedDownload:
      let failures = min(6, (window?.downloadFailures ?? 0) + 1)
      window?.downloadFailures = failures
    }
    do {
      beforeWrite()
      guard admission.allows(token) else { return }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(window)
      guard data.count <= 4096 else { throw UsageError.invalid }
      try data.write(to: file, options: .atomic)
    } catch { _ = fail("Usage data could not be saved safely. Reporting is off for this session.") }
  }
  func check() async {
    guard let revision = token, !unsafe, activeAttempt == nil, let value = window, let configuration
    else { return }
    let elapsed = clock.elapsed() - anchor
    guard elapsed.isFinite, initialAge + max(0, elapsed) >= 604800 else { return }
    do { try clear() } catch {
      _ = fail("Usage data could not be cleared safely. No report was sent.")
      return
    }
    let attempt = UUID()
    activeAttempt = attempt
    await beforeSend()
    guard admission.allows(revision) else {
      if activeAttempt == attempt { activeAttempt = nil }
      return
    }
    let bucket =
      value.downloadFailures == 0
      ? "zero"
      : value.downloadFailures == 1
        ? "one" : value.downloadFailures < 6 ? "two_to_five" : "six_plus"
    let body: [String: Any] = [
      "api_key": configuration.token, "event": "humstead_usage_summary",
      "distinct_id": UUID().uuidString,
      "properties": [
        "schemaVersion": 1, "appVersion": configuration.version,
        "usedAmbience": value.usedAmbience, "usedAmbienceOnly": value.usedAmbienceOnly,
        "usedTimer": value.usedTimer, "usedMenuBar": value.usedMenuBar,
        "usedDownloads": value.usedDownloads,
        "downloadFailures": bucket, "$process_person_profile": false, "$geoip_disable": true,
      ],
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else {
      activeAttempt = nil
      return
    }
    let started = admission.lock.withLock {
      guard admission.enabled, admission.revision == revision else { return false }
      transport.send(data) { [weak self] in Task { await self?.finished(attempt) } }
      return true
    }
    if !started { activeAttempt = nil }
  }
  private func finished(_ attempt: UUID) { if activeAttempt == attempt { activeAttempt = nil } }
  private func clear() throws {
    if FileManager.default.fileExists(atPath: file.path) {
      try FileManager.default.removeItem(at: file)
    }
    window = nil
    initialAge = 0
  }
  @discardableResult private func announce(_ state: Presentation) -> Presentation {
    var value = state
    admission.lock.withLock {
      value.revision = admission.revision
      value.enabled = admission.enabled
    }
    publish(value)
    return value
  }
  @discardableResult private func fail(_ message: String) -> Presentation {
    unsafe = true
    close()
    return announce(Presentation(warning: message))
  }
}
private enum UsageError: Error { case invalid }

final class UsageTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var offset = 0.0
  func advance() { lock.withLock { offset += 604800 } }
  func wall() -> Double { lock.withLock { Date().timeIntervalSince1970 + offset } }
  func elapsed() -> Double { lock.withLock { UsageClock.monotonic() + offset } }
}
