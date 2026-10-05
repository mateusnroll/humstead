import MediaPlayer
import Testing

@MainActor
struct SystemMediaTests {
  @Test func metadataAndCommandLifecycle() {
    var commands: [SystemMediaBridge.Command] = []
    let bridge = SystemMediaBridge { commands.append($0) }
    bridge.update(
      title: "Rainy Window", artist: "Humstead", station: "Mellow", playing: true,
      nextEnabled: false)
    #expect(
      MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String
        == "Rainy Window")
    #expect(MPNowPlayingInfoCenter.default().playbackState == .playing)
    #expect(!MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled)
    bridge.receive(.pause)
    #expect(commands == [.pause])
    bridge.stop()
    bridge.receive(.play)
    #expect(commands == [.pause])
    #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
  }
}
