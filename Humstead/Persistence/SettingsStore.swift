import Foundation

final class SettingsStore: @unchecked Sendable {
  struct Loaded: Sendable {
    var settings = MixSettings()
    var warning: String?
    var readOnly = false
  }
  private struct Header: Decodable { let schemaVersion: Int }
  private let queue = DispatchQueue(label: "com.mateusnroll.humstead.settings")
  private let directory: URL
  private let warning: @Sendable (String) -> Void
  private var readOnly = false
  private var pending: MixSettings?
  private var saveWork: DispatchWorkItem?
  private var generation = 0

  init(directory: URL, warning: @escaping @Sendable (String) -> Void = { _ in }) {
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
      let data = try Data(contentsOf: file)
      if let header = try? JSONDecoder().decode(Header.self, from: data), header.schemaVersion > 1 {
        readOnly = true
        return Loaded(
          warning:
            "These settings were saved by a newer Humstead. Defaults are shown; your file will not be changed.",
          readOnly: true)
      }
      guard data.count <= 2_000_000 else { throw SettingsError.invalid }
      let settings = try JSONDecoder().decode(MixSettings.self, from: data).validated()
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
  func save(_ settings: MixSettings) {
    queue.async { [self] in
      guard !readOnly else { return }
      do { pending = try settings.validated() } catch {
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
      try encoder.encode(pending).write(to: file, options: .atomic)
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
