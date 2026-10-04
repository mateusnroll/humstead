import AVFoundation
import Foundation

protocol AudioPlaying: AnyObject {
  var volume: Float { get set }
  var currentTime: TimeInterval { get }
  var numberOfLoops: Int { get set }
  var deviceCurrentTime: TimeInterval { get }
  func play(atTime: TimeInterval) -> Bool
  func prepare() -> Bool
  func play() -> Bool
  func pause()
  func stop()
}

extension AudioPlaying {
  var numberOfLoops: Int {
    get { 0 }
    set {}
  }
  var deviceCurrentTime: TimeInterval { 0 }
  func play(atTime: TimeInterval) -> Bool { play() }
}

nonisolated final class NativeAudioPlayer: NSObject, AudioPlaying, AVAudioPlayerDelegate {
  private let player: AVAudioPlayer
  private let completion: @Sendable (Bool) -> Void

  init(url: URL, completion: @escaping @Sendable (Bool) -> Void) throws {
    player = try AVAudioPlayer(contentsOf: url)
    self.completion = completion
    super.init()
    player.delegate = self
  }

  var volume: Float {
    get { player.volume }
    set { player.volume = newValue }
  }
  var currentTime: TimeInterval { player.currentTime }
  var numberOfLoops: Int {
    get { player.numberOfLoops }
    set { player.numberOfLoops = newValue }
  }
  var deviceCurrentTime: TimeInterval { player.deviceCurrentTime }
  func play(atTime: TimeInterval) -> Bool { player.play(atTime: atTime) }
  func prepare() -> Bool { player.prepareToPlay() }
  func play() -> Bool { player.play() }
  func pause() { player.pause() }
  func stop() { player.stop() }
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    completion(flag)
  }
  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
    completion(false)
  }
}

struct PlaybackState: Sendable {
  var catalog: Catalog?
  var stationID = "mellow"
  var trackID: String?
  var playbackRequested = false
  var isPlaying = false
  var volume: Float = 0.65
  var error: String?
  var mix: [String: AmbienceLevel] = [:]
  var activeLayers: Set<String> = []
  var layerErrors: [String: String] = [:]
  var expiredTimer: UInt64?
  var requestID: UInt64 = 0
  var sequence: UInt64 = 0
}

// All mutable state and player calls belong to queue; callers exchange Sendable snapshots only.
final class AudioController: @unchecked Sendable {
  typealias Factory =
    @Sendable (Catalog.Asset, @escaping @Sendable (Bool) -> Void) throws -> any AudioPlaying
  private let queue = DispatchQueue(label: "com.mateusnroll.humstead.audio", qos: .userInitiated)
  private let factory: Factory
  private let publish: @Sendable (PlaybackState) -> Void
  private var state = PlaybackState()
  private var player: (any AudioPlaying)?
  private var bag = ShuffleBag(tracks: [])
  private var generation: UInt64 = 0
  private var failedTracks: Set<String> = []
  private var layers: [String: any AudioPlaying] = [:]
  private var layerGenerations: [String: UInt64] = [:]
  private var musicPlaying = false
  private var masterGain: Float = 1
  private var fade: DispatchSourceTimer?
  private var fadeGeneration: UInt64 = 0

  init(
    catalog: Catalog, factory: @escaping Factory,
    publish: @escaping @Sendable (PlaybackState) -> Void = { _ in }
  ) {
    self.factory = factory
    self.publish = publish
    state.catalog = catalog
  }

  init(
    bundle: Bundle, settings: MixSettings = MixSettings(),
    publish: @escaping @Sendable (PlaybackState) -> Void
  ) {
    factory = { asset, completion in
      let url = try Catalog.verifiedURL(for: asset, bundle: bundle)
      return try NativeAudioPlayer(url: url, completion: completion)
    }
    self.publish = publish
    queue.async { [self] in
      do {
        state.catalog = try Catalog.load(bundle: bundle)
        state.volume = Float(settings.musicVolume)
        select(settings.currentStationID)
        configureMix(settings.mix)
      } catch {
        state.error = "The bundled library could not be read. Please reinstall Humstead."
      }
      emit()
    }
  }

  func selectStation(_ id: String, requestID: UInt64) {
    enqueue(requestID) { $0.select(id) }
  }

  private func select(_ id: String) {
    guard let station = state.catalog?.stations.first(where: { $0.id == id }) else { return }
    state.stationID = id
    bag = ShuffleBag(tracks: station.assetIDs)
    failedTracks.removeAll()
    prepareNext()
  }

  func setPlaying(_ playing: Bool, requestID: UInt64) {
    enqueue(requestID) { owner in
      let deviceTime =
        (owner.player?.deviceCurrentTime ?? owner.layers.values.first?.deviceCurrentTime ?? 0)
        + 0.02
      owner.state.playbackRequested = playing
      if !playing { owner.pauseLayers() }
      if !playing || owner.state.volume == 0 {
        owner.player?.pause()
        owner.musicPlaying = false
      } else if let player = owner.player {
        if player.play(atTime: deviceTime) {
          owner.musicPlaying = true
          owner.state.error = nil
        } else {
          if let id = owner.state.trackID { owner.failedTracks.insert(id) }
          owner.prepareNext()
        }
      } else {
        owner.failedTracks.removeAll()
        owner.prepareNext()
      }
      if playing { owner.startLayers(atTime: deviceTime) }
    }
  }

  func next(requestID: UInt64) {
    enqueue(requestID) { owner in
      guard owner.state.volume > 0 else { return }
      owner.failedTracks.removeAll()
      owner.prepareNext()
    }
  }

  func setVolume(_ value: Float, requestID: UInt64) {
    enqueue(requestID) { owner in
      guard value.isFinite else { return }
      let wasSilent = owner.state.volume == 0
      owner.state.volume = min(1, max(0, value))
      owner.player?.volume = owner.state.volume * owner.masterGain
      if owner.state.volume == 0 {
        owner.player?.pause()
        owner.musicPlaying = false
      } else if wasSilent && owner.state.playbackRequested {
        if let player = owner.player, player.play() {
          owner.musicPlaying = true
        } else {
          if let id = owner.state.trackID { owner.failedTracks.insert(id) }
          owner.prepareNext()
        }
      }
    }
  }

  private func enqueue(_ requestID: UInt64, action: @escaping @Sendable (AudioController) -> Void) {
    queue.async { [self] in
      guard requestID >= state.requestID else { return }
      state.requestID = requestID
      action(self)
      emit()
    }
  }

  private func prepareNext() {
    generation += 1
    player?.stop()
    player = nil
    musicPlaying = false
    state.trackID = nil
    guard let catalog = state.catalog,
      let station = catalog.stations.first(where: { $0.id == state.stationID })
    else { return }
    // Two bag passes cover every candidate even when the first bag was partially consumed.
    for _ in 0..<(station.assetIDs.count * 2) {
      guard let id = bag.next(), !failedTracks.contains(id), let asset = catalog.asset(id) else {
        continue
      }
      generation += 1
      let token = generation
      do {
        let candidate = try factory(asset) { [weak self] success in
          self?.finished(generation: token, successfully: success)
        }
        candidate.volume = state.volume * masterGain
        let shouldPlay = state.playbackRequested && state.volume > 0
        guard candidate.prepare(), !shouldPlay || candidate.play() else {
          candidate.stop()
          failedTracks.insert(id)
          continue
        }
        player = candidate
        state.trackID = id
        musicPlaying = shouldPlay
        state.error = nil
        return
      } catch {
        failedTracks.insert(id)
      }
    }
    if layers.isEmpty { state.playbackRequested = false }
    state.error = "This station’s audio could not be played. Try again or choose another station."
  }

  private func finished(generation token: UInt64, successfully: Bool) {
    queue.async { [self] in
      guard token == generation, musicPlaying, state.playbackRequested, state.volume > 0 else {
        return
      }
      if successfully {
        failedTracks.removeAll()
      } else if let id = state.trackID {
        failedTracks.insert(id)
      }
      prepareNext()
      emit()
    }
  }

  private func emit() {
    state.isPlaying = (musicPlaying && state.volume > 0) || !state.activeLayers.isEmpty
    state.sequence += 1
    publish(state)
  }

  func setMix(_ mix: [String: AmbienceLevel], requestID: UInt64) {
    enqueue(requestID) { $0.configureMix(mix) }
  }

  private func configureMix(_ mix: [String: AmbienceLevel]) {
    guard mix.values.allSatisfy({ $0.level.isFinite && (0...1).contains($0.level) }) else { return }
    guard mix.values.filter({ $0.enabled }).count <= 16 else {
      state.error = "Disable an ambience layer before enabling another. The limit is 16."
      return
    }
    state.mix = mix
    for id in Array(layers.keys) where mix[id]?.enabled != true {
      layers.removeValue(forKey: id)?.stop()
      state.activeLayers.remove(id)
      layerGenerations[id, default: 0] += 1
    }
    state.layerErrors = state.layerErrors.filter { mix[$0.key]?.enabled == true }
    for (id, value) in mix where value.enabled {
      if layers[id] == nil && state.layerErrors[id] == nil {
        guard let asset = state.catalog?.asset(id), asset.kind == "ambience" else {
          state.layerErrors[id] = "This ambience sound is unavailable."
          continue
        }
        layerGenerations[id, default: 0] += 1
        let token = layerGenerations[id]!
        do {
          let candidate = try factory(asset) { [weak self] _ in
            self?.layerEnded(id, generation: token)
          }
          candidate.numberOfLoops = -1
          guard candidate.prepare() else {
            candidate.stop()
            throw CatalogError.invalid
          }
          layers[id] = candidate
          state.layerErrors[id] = nil
        } catch {
          state.layerErrors[id] =
            "This ambience sound could not be played. Toggle it off and on to retry."
        }
      }
      layers[id]?.volume = Float(value.level) * masterGain
    }
    if state.playbackRequested { startLayers() }
  }

  private func layerEnded(_ id: String, generation token: UInt64) {
    queue.async { [self] in
      guard layerGenerations[id] == token, layers[id] != nil else { return }
      layers.removeValue(forKey: id)?.stop()
      state.activeLayers.remove(id)
      state.layerErrors[id] = "This ambience stopped unexpectedly. Toggle it off and on to retry."
      emit()
    }
  }

  private func startLayers(atTime: TimeInterval? = nil) {
    let time =
      atTime ?? (player?.deviceCurrentTime ?? layers.values.first?.deviceCurrentTime ?? 0) + 0.02
    for (id, layer) in layers
    where !state.activeLayers.contains(id) && state.layerErrors[id] == nil {
      if layer.play(atTime: time) {
        state.activeLayers.insert(id)
      } else {
        state.layerErrors[id] = "This ambience could not start. Toggle it off and on to retry."
      }
    }
  }

  private func pauseLayers() {
    for layer in layers.values { layer.pause() }
    state.activeLayers.removeAll()
  }

  func fadeOut(timerID: UInt64, requestID: UInt64) {
    enqueue(requestID) { owner in
      owner.cancelFadeOnQueue()
      let token = owner.fadeGeneration
      let start = ContinuousClock.now
      let timer = DispatchSource.makeTimerSource(queue: owner.queue)
      timer.schedule(deadline: .now(), repeating: .milliseconds(50))
      timer.setEventHandler { [weak owner] in
        guard let owner, owner.fadeGeneration == token else { return }
        let elapsed = start.duration(to: .now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        owner.masterGain = Float(max(0, 1 - seconds / 5))
        owner.applyGain()
        if seconds >= 5 {
          owner.player?.pause()
          owner.pauseLayers()
          owner.state.playbackRequested = false
          owner.musicPlaying = false
          owner.state.expiredTimer = timerID
          owner.cancelFadeOnQueue()
          owner.emit()
        }
      }
      owner.fade = timer
      timer.resume()
    }
  }

  func cancelFade(requestID: UInt64) {
    enqueue(requestID) { $0.cancelFadeOnQueue() }
  }
  private func cancelFadeOnQueue() {
    fadeGeneration += 1
    fade?.cancel()
    fade = nil
    masterGain = 1
    applyGain()
  }
  private func applyGain() {
    player?.volume = state.volume * masterGain
    for (id, layer) in layers { layer.volume = Float(state.mix[id]?.level ?? 0) * masterGain }
  }

  func snapshot() async -> PlaybackState {
    await withCheckedContinuation { continuation in
      queue.async { [self] in continuation.resume(returning: state) }
    }
  }

  func stop() {
    queue.async { [self] in
      generation += 1
      cancelFadeOnQueue()
      pauseLayers()
      for layer in layers.values { layer.stop() }
      layers.removeAll()
      player?.stop()
      player = nil
      musicPlaying = false
      state.playbackRequested = false
      emit()
    }
  }
}
