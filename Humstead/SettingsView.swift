import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: PlayerModel
  var body: some View {
    TabView(selection: $model.settingsPage) {
      DownloadsView(model: model)
        .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }.tag("downloads")
      CreditsView(model: model)
        .tabItem { Label("Credits", systemImage: "heart") }.tag("credits")
    }
    .frame(width: 600, height: 580)
  }
}

struct CreditsButton: View {
  @ObservedObject var model: PlayerModel
  var body: some View {
    if #available(macOS 14, *) {
      ModernCreditsButton(model: model)
    } else {
      Button("Credits") {
        model.settingsPage = "credits"
        openCredits()
      }.buttonStyle(.link)
    }
  }
}

@available(macOS 14, *)
private struct ModernCreditsButton: View {
  @ObservedObject var model: PlayerModel
  @Environment(\.openSettings) private var openSettings
  var body: some View {
    Button("Credits") {
      model.settingsPage = "credits"
      openSettings()
    }.buttonStyle(.link)
  }
}
