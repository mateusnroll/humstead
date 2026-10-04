import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var model: PlayerModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button(model.state.playbackRequested ? "Pause" : "Play", action: model.togglePlayback)
      .disabled(model.state.catalog == nil)
    Divider()
    ForEach(model.state.catalog?.stations ?? []) { station in
      Button {
        model.selectStation(station.id)
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
    }
    Button("Quit Humstead") { NSApp.terminate(nil) }
  }
}
