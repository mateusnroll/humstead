import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var model: PlayerModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button(model.state.playbackRequested ? "Pause" : "Play", action: model.toggleFromMenu)
      .disabled(model.state.catalog == nil)
    Divider()
    ForEach(model.state.catalog?.stations ?? []) { station in
      Button {
        model.stationFromMenu(station.id)
      } label: {
        if model.state.stationID == station.id {
          Label(station.title, systemImage: "checkmark")
        } else {
          Text(station.title)
        }
      }
    }
    Divider()
    Button("Show Humstead") {
      openWindow(id: "player")
      NSApp.activate(ignoringOtherApps: true)
      if NSApp.windows.contains(where: { $0.title == "Humstead" && $0.isVisible }) {
        model.menuWindowShown()
      }
    }
    Button("Quit Humstead") { NSApp.terminate(nil) }
  }
}
