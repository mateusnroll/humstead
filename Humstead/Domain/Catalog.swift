import CryptoKit
import Foundation

struct Catalog: Codable, Sendable {
  struct Asset: Codable, Identifiable, Sendable {
    let id: String
    let kind: String
    let resource: String
    let byteLength: Int
    let sha256: String
    let duration: Double
    let codec: String
    let title: String
    let creator: String
    let sourceURL: URL
    let profileURL: URL?
    let license: String
    let licenseURL: URL
    let attribution: String
    let modification: String
  }

  struct Station: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let assetIDs: [String]
  }

  let schemaVersion: Int
  let stations: [Station]
  let assets: [Asset]

  static func load(bundle: Bundle) throws -> Catalog {
    guard let url = bundle.url(forResource: "catalog", withExtension: "json") else {
      throw CatalogError.invalid
    }
    let data = try Data(contentsOf: url)
    guard data.count <= 2_000_000 else { throw CatalogError.invalid }
    let catalog = try JSONDecoder().decode(Catalog.self, from: data)
    try catalog.validate()
    return catalog
  }

  func validate() throws {
    guard schemaVersion == 1, !stations.isEmpty, assets.count <= 2000,
      Set(assets.map(\.id)).count == assets.count,
      Set(stations.map(\.id)).count == stations.count
    else { throw CatalogError.invalid }
    for asset in assets {
      guard !asset.id.isEmpty, ["music", "ambience"].contains(asset.kind),
        !asset.resource.isEmpty, !asset.resource.contains("/"),
        !asset.resource.contains("\\"), !asset.resource.contains(".."),
        ["m4a", "caf"].contains((asset.resource as NSString).pathExtension),
        asset.byteLength > 0, asset.byteLength <= 100_000_000,
        asset.duration.isFinite, asset.duration > 0,
        asset.sha256.count == 64, asset.sha256.allSatisfy({ $0.isHexDigit }),
        !asset.title.isEmpty, !asset.creator.isEmpty, !asset.attribution.isEmpty,
        asset.license == "CC0-1.0",
        asset.licenseURL == URL(string: "https://creativecommons.org/publicdomain/zero/1.0/"),
        Self.isHTTPS(asset.sourceURL), asset.profileURL.map(Self.isHTTPS) ?? true
      else { throw CatalogError.invalid }
    }
    for station in stations {
      guard !station.id.isEmpty, !station.title.isEmpty, !station.assetIDs.isEmpty,
        Set(station.assetIDs).count == station.assetIDs.count,
        station.assetIDs.allSatisfy({ id in assets.contains { $0.id == id && $0.kind == "music" } })
      else { throw CatalogError.invalid }
    }
  }

  static func isHTTPS(_ url: URL) -> Bool {
    url.scheme == "https" && !(url.host ?? "").isEmpty && url.user == nil && url.password == nil
  }

  func asset(_ id: String?) -> Asset? { assets.first { $0.id == id } }

  static func verifiedURL(for asset: Asset, bundle: Bundle) throws -> URL {
    guard let url = bundle.url(forResource: asset.resource, withExtension: nil) else {
      throw CatalogError.invalid
    }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard data.count == asset.byteLength, hash == asset.sha256 else { throw CatalogError.invalid }
    return url
  }
}

enum CatalogError: Error { case invalid }

extension Catalog {
  func merging(_ library: LibrarySnapshot) -> Catalog {
    var indexed: [String: Asset] = [:]
    for record in library.records {
      for asset in record.assets where !library.unavailable.contains(asset.id) {
        indexed[asset.id] = asset.metadata
      }
    }
    return Catalog(
      schemaVersion: schemaVersion,
      stations: stations.map { station in
        let extras = library.records.filter { $0.collection.stationID == station.id }
          .flatMap { $0.collection.assetIDs }.filter { indexed[$0] != nil }
        return Station(
          id: station.id, title: station.title,
          assetIDs: station.assetIDs + Set(extras).sorted())
      }, assets: assets + indexed.values.sorted { $0.id < $1.id })
  }
}
