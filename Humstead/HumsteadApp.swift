import AppKit
import SwiftUI

@main
struct HumsteadApp: App {
  @StateObject private var model = PlayerModel()
  @NSApplicationDelegateAdaptor(HumsteadDelegate.self) private var delegate

  var body: some Scene {
    Window("Humstead", id: "player") {
      ContentView(model: model)
        .onAppear { delegate.model = model }
    }
    .defaultSize(width: 380, height: 520)
    .commands {
      CommandMenu("Playback") {
        Button(model.state.playbackRequested ? "Pause" : "Play", action: model.togglePlayback)
          .keyboardShortcut("p", modifiers: .command)
        Button("Next track", action: model.next)
          .keyboardShortcut(.rightArrow, modifiers: .command)
          .disabled(!model.canNext)
      }
    }
    MenuBarExtra {
      MenuBarView(model: model)
    } label: {
      Image(systemName: "waveform").accessibilityLabel("Humstead")
    }
    Settings {
      CreditsView(model: model)
    }
  }
}

@MainActor
final class HumsteadDelegate: NSObject, NSApplicationDelegate {
  weak var model: PlayerModel?
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationWillTerminate(_ notification: Notification) { model?.stop() }
}
