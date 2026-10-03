import Combine
import Foundation

@MainActor
final class PlayerModel: ObservableObject {
  @Published private(set) var state = PlaybackState()
  private var controller: AudioController?
  private var requestID: UInt64 = 0

  init() {
    controller = AudioController(bundle: .main) { [weak self] state in
      Task { @MainActor [weak self] in self?.receive(state) }
    }
  }

  private func receive(_ snapshot: PlaybackState) {
    guard snapshot.requestID >= requestID, snapshot.sequence > state.sequence else { return }
    state = snapshot
  }

  var track: Catalog.Asset? { state.catalog?.asset(state.trackID) }

  func selectStation(_ id: String) {
    requestID += 1
    controller?.selectStation(id, requestID: requestID)
  }

  func togglePlayback() {
    requestID += 1
    state.playbackRequested.toggle()
    controller?.setPlaying(state.playbackRequested, requestID: requestID)
  }

  func next() {
    requestID += 1
    controller?.next(requestID: requestID)
  }

  func setVolume(_ volume: Double) {
    requestID += 1
    state.volume = Float(volume)
    controller?.setVolume(Float(volume), requestID: requestID)
  }

  func stop() { controller?.stop() }
}
