import Foundation
import MediaPlayer

@MainActor
final class SystemMediaBridge {
  enum Command: Sendable { case play, pause, toggle, next }
  private let action: (Command) -> Void
  private var targets: [(MPRemoteCommand, Any)] = []
  private var active = true

  init(action: @escaping (Command) -> Void) {
    self.action = action
    let center = MPRemoteCommandCenter.shared()
    for (command, intent) in [
      (center.playCommand, Command.play), (center.pauseCommand, .pause),
      (center.togglePlayPauseCommand, .toggle), (center.nextTrackCommand, .next),
    ] {
      let target = command.addTarget { [weak self] _ in
        Task { @MainActor [weak self] in self?.receive(intent) }
        return .success
      }
      targets.append((command, target))
      command.isEnabled = true
    }
    center.previousTrackCommand.isEnabled = false
    center.changePlaybackPositionCommand.isEnabled = false
    center.seekForwardCommand.isEnabled = false
    center.seekBackwardCommand.isEnabled = false
  }
  func receive(_ command: Command) {
    guard active else { return }
    action(command)
  }
  func update(title: String, artist: String, station: String, playing: Bool, nextEnabled: Bool) {
    guard active else { return }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: title, MPMediaItemPropertyArtist: artist,
      MPMediaItemPropertyAlbumTitle: station,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
    ]
    MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = nextEnabled
  }
  func stop() {
    active = false
    for (command, target) in targets { command.removeTarget(target) }
    targets.removeAll()
    MPNowPlayingInfoCenter.default().playbackState = .stopped
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }
}
