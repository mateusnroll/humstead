import SwiftUI

struct CreditsView: View {
  @ObservedObject var model: PlayerModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("Credits").font(.largeTitle)
        Text(
          "Made by generous people. Every recording is offered under CC0 1.0. Visit the creators, share their work, and explore their music."
        )
        .foregroundStyle(.secondary)
        ForEach(model.state.catalog?.assets ?? []) { asset in
          VStack(alignment: .leading, spacing: 8) {
            Text(asset.title).font(.headline)
            Text(asset.attribution)
            Link(asset.sourceURL.absoluteString, destination: asset.sourceURL)
              .accessibilityIdentifier("original-source")
            if let profile = asset.profileURL {
              Link(profile.absoluteString, destination: profile)
                .accessibilityIdentifier("creator-profile")
            }
            Link("CC0 1.0 — Public Domain Dedication", destination: asset.licenseURL)
            Text(asset.modification).font(.caption).foregroundStyle(.secondary)
          }
          .textSelection(.enabled)
          Divider()
        }
        Text("Humstead source code is MIT licensed. Audio keeps its own license.").font(.caption)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(24)
    }
    .frame(width: 560, height: 520)
    .navigationTitle("Credits")
  }
}
