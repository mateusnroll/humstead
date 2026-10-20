import SwiftUI

struct CreditsView: View {
  @ObservedObject var model: PlayerModel
  @FocusState private var focused: CreditLink?

  private enum CreditLink: Hashable {
    case source(String)
    case profile(String)
    case license(String)
    var assetID: String {
      switch self {
      case .source(let id), .profile(let id), .license(let id): return id
      }
    }
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 24) {
          Text("Credits").font(.largeTitle)
          Text(
            "Made by generous people. Each recording keeps its own open license. Visit the creators, share their work, and explore their music."
          )
          .foregroundStyle(.secondary)
          let downloadedIDs = Set(model.libraryState.records.flatMap(\.assets).map(\.id))
          let credits = model.credits
          VStack(alignment: .leading, spacing: 24) {
            ForEach(credits.filter { !downloadedIDs.contains($0.id) }) { asset in
              credit(asset).id(asset.id)
            }
          }
          ForEach(credits.filter { downloadedIDs.contains($0.id) }) { asset in
            credit(asset).id(asset.id)
          }
          Text("Humstead source code is MIT licensed. Audio keeps its own license.").font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
      }
      .onChange(of: focused) { link in
        if let link { proxy.scrollTo(link.assetID, anchor: .center) }
      }
    }
    .frame(width: 560, height: 520)
    .navigationTitle("Credits")
  }
  @ViewBuilder
  private func credit(_ asset: Catalog.Asset) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(asset.title).font(.headline)
      Text(asset.attribution)
      Link(asset.sourceURL.absoluteString, destination: asset.sourceURL)
        .accessibilityIdentifier("original-source")
        .focused($focused, equals: .source(asset.id))
      if let profile = asset.profileURL {
        Link(profile.absoluteString, destination: profile)
          .accessibilityIdentifier("creator-profile")
          .focused($focused, equals: .profile(asset.id))
      }
      Link(
        asset.license == "CC0-1.0" ? "CC0 1.0 — Public Domain Dedication" : asset.license,
        destination: asset.licenseURL
      )
      .accessibilityIdentifier("credit-license-\(asset.id)")
      .focused($focused, equals: .license(asset.id))
      Text(asset.modification).font(.caption).foregroundStyle(.secondary)
    }
    .textSelection(.enabled)
    Divider()
  }

}
