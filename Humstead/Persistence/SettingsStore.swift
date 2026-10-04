import Foundation

final class SettingsStore: @unchecked Sendable {
  struct Loaded: Sendable {
    var settings = MixSettings()
    var warning: String?
    var readOnly = false
  }
  private struct Header: Decodable { let schemaVersion: Int }
  // Accommodates 2,000 optional IDs in all 15 station/preset mixes.
  private static let maximumBytes = 8_000_000
  private let queue = DispatchQueue(label: "com.mateusnroll.humstead.settings")
  private let directory: URL
  private let warning: @Sendable (String) -> Void
  private var readOnly = false
  private var availableSounds: Set<String>
  private var pending: MixSettings?
  private var saveWork: DispatchWorkItem?
  private var generation = 0

  init(
    directory: URL, availableSounds: Set<String> = Set(MixSettings.soundIDs),
    warning: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.availableSounds = availableSounds
    self.directory = directory
    self.warning = warning
  }
  private var file: URL { directory.appendingPathComponent("settings.json") }

  func load() async -> Loaded {
    await withCheckedContinuation { continuation in
      queue.async { [self] in continuation.resume(returning: read()) }
    }
  }
  private func read() -> Loaded {
    guard FileManager.default.fileExists(atPath: file.path) else { return Loaded() }
    do {
      let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= Self.maximumBytes else {
        readOnly = true
        return Loaded(
          warning:
            "These settings exceed the supported size. The original file is unchanged and saving is disabled.",
          readOnly: true)
      }
      let data = try Data(contentsOf: file)
      if let header = try? JSONDecoder().decode(Header.self, from: data), header.schemaVersion > 1 {
        readOnly = true
        return Loaded(
          warning:
            "These settings were saved by a newer Humstead. Defaults are shown; your file will not be changed.",
          readOnly: true)
      }
      guard data.count <= Self.maximumBytes else { throw SettingsError.invalid }
      let settings = try JSONDecoder().decode(MixSettings.self, from: data).validated(
        availableSounds: availableSounds)
      return Loaded(settings: settings)
    } catch {
      do {
        let backup = directory.appendingPathComponent("settings-recovery-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: file, to: backup)
      } catch {
        readOnly = true
        return Loaded(
          warning:
            "Your settings could not be recovered safely. Defaults are shown and saving is disabled for this session.",
          readOnly: true)
      }
      pending = MixSettings()
      writePending()
      return Loaded(
        warning:
          "Your unreadable settings were preserved in a recovery file. Humstead is using defaults.")
    }
  }
  func setAvailableSounds(_ sounds: Set<String>) {
    queue.async { self.availableSounds = sounds }
  }
  func save(_ settings: MixSettings) {
    queue.async { [self] in
      guard !readOnly else { return }
      do { pending = try settings.validated(availableSounds: availableSounds) } catch {
        warning("These settings could not be saved. Your last saved mix is unchanged.")
        return
      }
      generation += 1
      let token = generation
      saveWork?.cancel()
      let work = DispatchWorkItem { [weak self] in
        guard let self, self.generation == token else { return }
        self.writePending()
      }
      saveWork = work
      queue.asyncAfter(deadline: .now() + .milliseconds(250), execute: work)
    }
  }
  private func writePending() {
    guard !readOnly, let pending else { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(pending)
      guard data.count <= Self.maximumBytes else { throw SettingsError.invalid }
      try data.write(to: file, options: .atomic)
      self.pending = nil
    } catch {
      warning("Your changes could not be saved. Your last saved mix is unchanged.")
    }
  }
  func flush(timeout: TimeInterval) -> Bool {
    let done = DispatchSemaphore(value: 0)
    queue.async { [self] in
      generation += 1
      saveWork?.cancel()
      writePending()
      done.signal()
    }
    return done.wait(timeout: .now() + timeout) == .success
  }
}
