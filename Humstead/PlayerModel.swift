import Combine
import Foundation

@MainActor
final class PlayerModel: ObservableObject {
  @Published private(set) var state = PlaybackState()
  @Published private(set) var settings = MixSettings()
  @Published private(set) var persistenceWarning: String?
  @Published private(set) var sleepTimer = SleepTimer()
  @Published private(set) var countdown = 0
  private var controller: AudioController?
  private var store: SettingsStore?
  private var media: SystemMediaBridge?
  private var routes: AudioRouteObserver?
  private var timerTask: Task<Void, Never>?
  private var requestID: UInt64 = 0
  private var stopped = false
  private let clockStart = ContinuousClock.now

  init() {
    var directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Humstead")
    let arguments = ProcessInfo.processInfo.arguments
    if Bundle.main.bundleIdentifier == "com.mateusnroll.humstead.testing",
      let index = arguments.firstIndex(of: "--test-settings"), arguments.indices.contains(index + 1)
    {
      let name = arguments[index + 1]
      if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
        directory = directory.appendingPathComponent("Tests").appendingPathComponent(name)
      }
    }
    store = SettingsStore(directory: directory) { [weak self] warning in
      Task { @MainActor [weak self] in self?.persistenceWarning = warning }
    }
    Task { [weak self] in
      guard let self, let store else { return }
      let loaded = await store.load()
      guard !stopped else { return }
      settings = loaded.settings
      persistenceWarning = loaded.warning
      controller = AudioController(bundle: .main, settings: settings) { [weak self] state in
        Task { @MainActor [weak self] in self?.receive(state) }
      }
      media = SystemMediaBridge { [weak self] command in
        guard let self else { return }
        switch command {
        case .play: setPlaying(true)
        case .pause: setPlaying(false)
        case .toggle: togglePlayback()
        case .next: next()
        }
      }
      routes = AudioRouteObserver { [weak self] event in
        guard let self else { return }
        setPlaying(false)
        if event == .wake { tick() }
      }
    }
  }
  private var now: Double {
    let elapsed = clockStart.duration(to: .now).components
    return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
  }
  private func receive(_ snapshot: PlaybackState) {
    guard !stopped, snapshot.requestID >= requestID, snapshot.sequence > state.sequence else {
      return
    }
    state = snapshot
    if let expired = snapshot.expiredTimer, sleepTimer.finish(generation: expired) {
      timerTask?.cancel()
      countdown = 0
    }
    let station = state.catalog?.stations.first { $0.id == state.stationID }?.title ?? "Humstead"
    media?.update(
      title: state.volume > 0 ? track?.title ?? station : settings.presetTitle,
      artist: state.volume > 0 ? track?.creator ?? "Humstead" : "Humstead",
      station: station, playing: state.isPlaying, nextEnabled: canNext)
  }
  var track: Catalog.Asset? { state.catalog?.asset(state.trackID) }
  var canNext: Bool { state.volume > 0 && track != nil }
  private func intent() -> UInt64 {
    requestID += 1
    return requestID
  }
  private func persist() { store?.save(settings) }

  func selectStation(_ id: String) {
    guard controller != nil else { return }
    settings.selectStation(id)
    controller?.selectStation(settings.currentStationID, requestID: intent())
    controller?.setMix(settings.mix, requestID: intent())
    persist()
  }
  func selectPreset(_ id: String) {
    settings.selectPreset(id)
    controller?.setMix(settings.mix, requestID: intent())
    persist()
  }
  func setLayer(_ id: String, enabled: Bool? = nil, level: Double? = nil) {
    let current = settings.mix[id] ?? AmbienceLevel()
    settings.setLayer(id, enabled: enabled ?? current.enabled, level: level ?? current.level)
    controller?.setMix(settings.mix, requestID: intent())
    persist()
  }
  func resetAmbience() {
    settings.resetAmbience()
    controller?.setMix(settings.mix, requestID: intent())
    persist()
  }
  func togglePlayback() { setPlaying(!state.playbackRequested) }
  func setPlaying(_ playing: Bool) {
    guard !stopped, controller != nil else { return }
    if playing && sleepTimer.isFading { cancelTimer() }
    state.playbackRequested = playing
    controller?.setPlaying(playing, requestID: intent())
  }
  func next() {
    guard canNext else { return }
    controller?.next(requestID: intent())
  }
  func setVolume(_ volume: Double) {
    guard volume.isFinite, (0...1).contains(volume) else { return }
    settings.musicVolume = volume
    state.volume = Float(volume)
    controller?.setVolume(Float(volume), requestID: intent())
    persist()
  }
  func startTimer(_ minutes: Int) {
    cancelTimer()
    guard [15, 30, 60].contains(minutes) else { return }
    sleepTimer.start(minutes: minutes, now: now)
    tick()
    timerTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        self?.tick()
      }
    }
  }
  func cancelTimer() {
    timerTask?.cancel()
    timerTask = nil
    sleepTimer.cancel()
    countdown = 0
    controller?.cancelFade(requestID: intent())
  }
  private func tick() {
    countdown = sleepTimer.remaining(now: now)
    switch sleepTimer.advance(now: now, playing: state.isPlaying && state.playbackRequested) {
    case .none: break
    case .fade(let token): controller?.fadeOut(timerID: token, requestID: intent())
    case .pause:
      setPlaying(false)
      timerTask?.cancel()
    }
  }
  func stop() {
    guard !stopped else { return }
    stopped = true
    timerTask?.cancel()
    routes?.stop()
    media?.stop()
    controller?.stop()
    _ = store?.flush(timeout: 1)
  }
}
