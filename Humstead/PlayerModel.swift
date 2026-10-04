import Combine
import Foundation

@MainActor
final class PlayerModel: ObservableObject {
  @Published private(set) var state = PlaybackState()
  @Published private(set) var settings = MixSettings()
  @Published private(set) var persistenceWarning: String?
  @Published private(set) var layerMessage: String?
  @Published private(set) var sleepTimer = SleepTimer()
  @Published private(set) var countdown = 0
  @Published var settingsPage = "downloads"
  @Published private(set) var downloads = DownloadState()
  @Published private(set) var libraryState = LibrarySnapshot()
  @Published private(set) var downloadError: String?
  @Published private(set) var downloadingCollectionID: String?
  @Published private(set) var failedDownloadID: String?
  @Published private(set) var removing = false
  private var library: LibraryStore?
  private var bundled: Catalog?
  private var downloadCoordinator: DownloadCoordinator?
  private var refreshTask: Task<Void, Never>?
  private var removalTask: Task<Void, Never>?
  @Published private var downloadTask: Task<Void, Never>?

  private var controller: AudioController?
  private var store: SettingsStore?
  private var media: SystemMediaBridge?
  private var routes: AudioRouteObserver?
  private var timerTask: Task<Void, Never>?
  private var requestID: UInt64 = 0
  private var stopped = false
  private let clockStart = ContinuousClock.now

  init(directory suppliedDirectory: URL? = nil, bundle: Bundle = .main) {
    var directory =
      suppliedDirectory
      ?? FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
        "Humstead")
    let arguments = ProcessInfo.processInfo.arguments
    if Bundle.main.bundleIdentifier == "com.mateusnroll.humstead.testing",
      let index = arguments.firstIndex(of: "--test-settings"), arguments.indices.contains(index + 1)
    {
      let name = arguments[index + 1]
      if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
        directory = directory.appendingPathComponent("Tests").appendingPathComponent(name)
      }
    }
    let storageDirectory = directory
    Task { [weak self] in
      guard let self else { return }
      let catalog: Catalog
      do { catalog = try await Task.detached { try Catalog.load(bundle: bundle) }.value } catch {
        state.error = "The bundled library could not be read. Please reinstall Humstead."
        return
      }
      guard !stopped else { return }
      bundled = catalog
      let library = LibraryStore(directory: storageDirectory, bundled: catalog, bundle: bundle)
      self.library = library
      libraryState = await library.load()
      let available = catalog.merging(libraryState)
      let sounds = Set(available.assets.filter { $0.kind == "ambience" }.map(\.id))
      let store = SettingsStore(directory: storageDirectory, availableSounds: sounds) {
        [weak self] warning in
        Task { @MainActor [weak self] in self?.persistenceWarning = warning }
      }
      self.store = store
      let loaded = await store.load()
      guard !stopped else { return }
      settings = loaded.settings
      persistenceWarning = loaded.warning
      controller = AudioController(
        bundle: bundle, settings: settings, catalog: available, library: library
      ) { [weak self] state in
        Task { @MainActor [weak self] in self?.receive(state) }
      }
      var origin: DownloadOrigin?
      if let value = bundle.object(forInfoDictionaryKey: "HumsteadDownloadOrigin") as? String,
        let url = URL(string: value)
      {
        origin = try? DownloadOrigin(url)
      }
      if Bundle.main.bundleIdentifier == "com.mateusnroll.humstead.testing",
        let index = arguments.firstIndex(of: "--test-download-origin"),
        arguments.indices.contains(index + 1),
        let url = URL(string: arguments[index + 1]), url.host == "127.0.0.1"
      {
        origin = try? DownloadOrigin(url, testing: true)
      }
      let coordinator = DownloadCoordinator(
        origin: origin, library: library, bundled: catalog,
        publish: {
          [weak self] snapshot in
          Task { @MainActor [weak self] in
            guard let self, !stopped, snapshot.sequence > downloads.sequence else { return }
            downloads = snapshot
          }
        })
      downloadCoordinator = coordinator
      await coordinator.load()
      guard !stopped else { return }
      refreshTask = Task { [weak self] in
        while !Task.isCancelled {
          await coordinator.refresh(manual: false)
          do { try await Task.sleep(for: .seconds(3600)) } catch { return }
          guard self?.stopped == false else { return }
        }
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
        if event == .wake {
          tick()
          Task { await downloadCoordinator?.wake() }
        }
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
    guard !stopped, controller != nil else { return }
    layerMessage = nil
    settings.selectStation(id)
    controller?.selectStation(settings.currentStationID, requestID: intent())
    controller?.setMix(settings.mix, requestID: intent())
    persist()
  }
  func selectPreset(_ id: String) {
    guard !stopped, controller != nil else { return }
    layerMessage = nil
    settings.selectPreset(id)
    controller?.setMix(settings.mix, requestID: intent())
    persist()
  }
  func setLayer(_ id: String, enabled: Bool? = nil, level: Double? = nil) {
    guard !stopped, controller != nil else { return }
    let current = settings.mix[id] ?? AmbienceLevel()
    guard
      settings.setLayer(
        id, enabled: enabled ?? current.enabled, level: level ?? current.level,
        availableSounds: Set(sounds.map(\.id)))
    else {
      layerMessage = "Disable an ambience layer before enabling another. The limit is 16."
      return
    }
    layerMessage = nil
    controller?.setMix(settings.mix, requestID: intent())
    persist()
  }
  func resetAmbience() {
    guard !stopped, controller != nil else { return }
    layerMessage = nil
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
    guard !stopped, controller != nil else { return }
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
  var sounds: [Catalog.Asset] { state.catalog?.assets.filter { $0.kind == "ambience" } ?? [] }
  var credits: [Catalog.Asset] {
    var values = Dictionary(uniqueKeysWithValues: (bundled?.assets ?? []).map { ($0.id, $0) })
    for asset in libraryState.records.flatMap(\.assets) { values[asset.id] = asset.metadata }
    return values.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }
  var downloadCollections: [DownloadCatalog.Collection] {
    var values = Dictionary(
      uniqueKeysWithValues: libraryState.records.map { ($0.collection.id, $0.collection) })
    for collection in downloads.catalog?.collections ?? [] { values[collection.id] = collection }
    return values.values.sorted { $0.label < $1.label }
  }
  var downloadBusy: Bool { downloads.activeID != nil || downloadTask != nil || removing }
  func checkForUpdates() {
    guard !stopped else { return }
    Task { await downloadCoordinator?.refresh(manual: true) }
  }
  func downloadPlan(_ id: String) async -> DownloadPlan? {
    guard !stopped, !downloadBusy, !libraryState.readOnly else { return nil }
    do { return try await downloadCoordinator?.plan(id) } catch {
      downloadError = "This collection is unavailable. Check for updates and try again."
      return nil
    }
  }
  func install(_ plan: DownloadPlan) {
    guard !stopped, !downloadBusy, !libraryState.readOnly else { return }
    downloadError = nil
    failedDownloadID = nil
    downloadingCollectionID = plan.record.collection.id
    downloadTask = Task { [weak self] in
      guard let self, let downloadCoordinator else { return }
      defer {
        downloadTask = nil
        downloadingCollectionID = nil
      }
      guard !stopped, !Task.isCancelled else { return }
      do {
        try await downloadCoordinator.install(plan)
        await refreshLibrary()
      } catch {
        let result = await downloadCoordinator.snapshot()
        guard !stopped else { return }
        downloadError = result.message
        if !(error is CancellationError) { failedDownloadID = plan.record.collection.id }
      }
    }
  }
  func cancelDownload() {
    downloadTask?.cancel()
    Task { await downloadCoordinator?.cancel() }
  }
  private func refreshLibrary() async {
    guard !stopped, !Task.isCancelled, let library, let bundled else { return }
    let snapshot = await library.snapshot()
    guard !stopped, !Task.isCancelled else { return }
    libraryState = snapshot
    let catalog = bundled.merging(libraryState)
    let sounds = Set(catalog.assets.filter { $0.kind == "ambience" }.map(\.id))
    store?.setAvailableSounds(sounds)
    do { settings = try settings.validated(availableSounds: sounds) } catch {
      persistenceWarning = "Some saved ambience could not be restored."
    }
    await controller?.refreshCatalog(catalog, bundled: bundled, mix: settings.mix)
    guard !stopped, !Task.isCancelled else { return }
    persist()
  }
  func removeCollection(_ id: String) {
    guard !stopped, !downloadBusy, !libraryState.readOnly, let library, let bundled else { return }
    removing = true
    downloadError = nil
    removalTask = Task {
      defer {
        removing = false
        removalTask = nil
      }
      guard !stopped, !Task.isCancelled else { return }
      var remaining = libraryState
      remaining.records.removeAll { $0.collection.id == id }
      let catalog = bundled.merging(remaining)
      let sounds = Set(catalog.assets.filter { $0.kind == "ambience" }.map(\.id))
      do {
        let updated = try settings.validated(availableSounds: sounds)
        await controller?.refreshCatalog(catalog, bundled: bundled, mix: updated.mix)
        guard !stopped, !Task.isCancelled else { return }
        try await library.remove(id)
        await refreshLibrary()
        guard !stopped, !Task.isCancelled else { return }
        downloadError =
          "Collection removed. Unavailable ambience is disabled in saved mixes; your levels are remembered."
      } catch {
        guard !stopped, !Task.isCancelled else { return }
        await controller?.refreshCatalog(
          bundled.merging(libraryState), bundled: bundled, mix: settings.mix)
        guard !stopped, !Task.isCancelled else { return }
        downloadError = "The collection could not be removed. Your installed library is unchanged."
      }
    }
  }

  func stop() {
    guard !stopped else { return }
    stopped = true
    timerTask?.cancel()
    refreshTask?.cancel()
    downloadTask?.cancel()
    removalTask?.cancel()
    Task { await downloadCoordinator?.wake() }
    routes?.stop()
    media?.stop()
    controller?.stop()
    _ = store?.flush(timeout: 1)
  }
}
