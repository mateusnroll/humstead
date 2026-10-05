import SwiftUI

struct PrivacyView: View {
  @ObservedObject var model: PlayerModel
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("Privacy").font(.title2)
        Toggle(
          "Share weekly usage summaries",
          isOn: Binding(get: { model.usageEnabled }, set: model.setUsageEnabled)
        )
        .disabled(!model.usageAvailable || model.usageChanging)
        if !model.usageAvailable {
          Text("Reporting is unavailable in this build.").foregroundStyle(.secondary)
        }
        Text(
          "Sharing is optional and off by default. Once a week, Humstead can send broad yes/no feature usage and a bucketed download-failure count to PostHog in the EU."
        )
        Text(
          "Each report gets a new random ID. Humstead sends no persistent identity, track names, artist links, listening history or exact listening times. Reports cannot measure how often one person returns."
        )
        Text(
          "The processor sees your source IP and when a report arrives. Production reporting requires IP discard, no enrichment or person profiles, a free allowance without paid overages, and one-year retention."
        )
        Text(
          "Turning sharing off stops collection and delivery and clears pending data on this Mac. Already accepted reports cannot be recalled. Sharing failures never interrupt listening."
        )
        if let warning = model.usageWarning {
          Text(warning).foregroundStyle(.secondary).accessibilityIdentifier("usage-warning")
          Button("Turn sharing off and clear pending data") { model.setUsageEnabled(false) }
        }
        if model.canAdvanceUsageWindow {
          Button("Advance reporting window", action: model.advanceUsageWindow)
        }
        Spacer(minLength: 0)
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
