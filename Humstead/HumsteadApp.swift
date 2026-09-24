import SwiftUI

@main
struct HumsteadApp: App {
  var body: some Scene {
    Window("Humstead", id: "player") {
      ContentView()
    }
    .defaultSize(width: 420, height: 300)
  }
}
