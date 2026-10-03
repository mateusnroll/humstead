import SwiftUI

@main
struct HumsteadApp: App {
  @StateObject private var model = PlayerModel()

  var body: some Scene {
    Window("Humstead", id: "player") {
      ContentView(model: model)
    }
    .defaultSize(width: 380, height: 520)
    .commands {
      CommandMenu("Playback") {
        Button(model.state.playbackRequested ? "Pause" : "Play", action: model.togglePlayback)
          .keyboardShortcut("p", modifiers: .command)
        Button("Next track", action: model.next)
          .keyboardShortcut(.rightArrow, modifiers: .command)
      }
    }
    Settings {
      CreditsView(model: model)
    }
  }
}
