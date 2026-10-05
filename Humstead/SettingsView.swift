import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: PlayerModel
  var body: some View {
    VStack(spacing: 0) {
      Picker("Settings section", selection: $model.settingsPage) {
        Text("Downloads").tag("downloads")
        Text("Privacy").tag("privacy")
        Text("Credits").tag("credits")
      }
      .pickerStyle(.segmented)
      .padding()
      Divider()
      switch model.settingsPage {
      case "privacy": PrivacyView(model: model)
      case "credits": CreditsView(model: model)
      default: DownloadsView(model: model)
      }
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
