import AVFoundation
import Foundation

protocol AudioPlaying: AnyObject {
  var volume: Float { get set }
  var currentTime: TimeInterval { get }
  func prepare() -> Bool
  func play() -> Bool
  func pause()
  func stop()
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

  init(
    catalog: Catalog, factory: @escaping Factory,
    publish: @escaping @Sendable (PlaybackState) -> Void = { _ in }
  ) {
    self.factory = factory
    self.publish = publish
    state.catalog = catalog
  }

  init(bundle: Bundle, publish: @escaping @Sendable (PlaybackState) -> Void) {
    factory = { asset, completion in
      let url = try Catalog.verifiedURL(for: asset, bundle: bundle)
      return try NativeAudioPlayer(url: url, completion: completion)
    }
    self.publish = publish
    queue.async { [self] in
      do {
        state.catalog = try Catalog.load(bundle: bundle)
        select("mellow")
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
      owner.state.playbackRequested = playing
      if !playing || owner.state.volume == 0 {
        owner.player?.pause()
        owner.state.isPlaying = false
      } else if let player = owner.player {
        if player.play() {
          owner.state.isPlaying = true
          owner.state.error = nil
        } else {
          if let id = owner.state.trackID { owner.failedTracks.insert(id) }
          owner.prepareNext()
        }
      } else {
        owner.failedTracks.removeAll()
        owner.prepareNext()
      }
    }
  }

  func next(requestID: UInt64) {
    enqueue(requestID) { owner in
      owner.failedTracks.removeAll()
      owner.prepareNext()
    }
  }

  func setVolume(_ value: Float, requestID: UInt64) {
    enqueue(requestID) { owner in
      guard value.isFinite else { return }
      let wasSilent = owner.state.volume == 0
      owner.state.volume = min(1, max(0, value))
      owner.player?.volume = owner.state.volume
      if owner.state.volume == 0 {
        owner.player?.pause()
        owner.state.isPlaying = false
      } else if wasSilent && owner.state.playbackRequested {
        if let player = owner.player, player.play() {
          owner.state.isPlaying = true
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
    state.isPlaying = false
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
        candidate.volume = state.volume
        let shouldPlay = state.playbackRequested && state.volume > 0
        guard candidate.prepare(), !shouldPlay || candidate.play() else {
          candidate.stop()
          failedTracks.insert(id)
          continue
        }
        player = candidate
        state.trackID = id
        state.isPlaying = shouldPlay
        state.error = nil
        return
      } catch {
        failedTracks.insert(id)
      }
    }
    state.playbackRequested = false
    state.error = "This station’s audio could not be played. Try again or choose another station."
  }

  private func finished(generation token: UInt64, successfully: Bool) {
    queue.async { [self] in
      guard token == generation, state.isPlaying, state.playbackRequested else { return }
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
    state.sequence += 1
    publish(state)
  }

  func snapshot() async -> PlaybackState {
    await withCheckedContinuation { continuation in
      queue.async { [self] in continuation.resume(returning: state) }
    }
  }

  func stop() {
    queue.async { [self] in
      generation += 1
      player?.stop()
      player = nil
      state.isPlaying = false
      state.playbackRequested = false
      emit()
    }
  }
}
