import Foundation

struct DownloadCatalog: Codable, Sendable {
  struct Collection: Codable, Identifiable, Sendable {
    let id: String
    let kind: String
    let version: Int
    let label: String
    let stationID: String?
    let assetIDs: [String]
    let totalBytes: Int
  }
  struct Asset: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let kind: String
    let sha256: String
    let byteLength: Int
    let codec: String
    let duration: Double
    let path: String
    let title: String
    let creator: String
    let originalSourceURL: URL
    let creatorProfileURL: URL?
    let license: String
    let licenseVersion: String
    let licenseURL: URL
    let attribution: String
    let modification: String
    let bundledEquivalent: String?

    var metadata: Catalog.Asset {
      Catalog.Asset(
        id: id, kind: kind, resource: (path as NSString).lastPathComponent,
        byteLength: byteLength, sha256: sha256, duration: duration, codec: codec,
        title: title, creator: creator, sourceURL: originalSourceURL, profileURL: creatorProfileURL,
        license: license == "CC0" ? "CC0-1.0" : "CC BY-\(licenseVersion)",
        licenseURL: licenseURL, attribution: attribution, modification: modification)
    }
  }
  let schemaVersion: Int
  let catalogVersion: Int
  let collections: [Collection]
  let assets: [Asset]

  static func decode(_ data: Data, bundled: Catalog? = nil) throws -> DownloadCatalog {
    guard data.count <= 2_000_000 else { throw DownloadError.invalidCatalog }
    let catalog = try JSONDecoder().decode(Self.self, from: data)
    try catalog.validate(bundled: bundled)
    return catalog
  }

  func validate(bundled: Catalog? = nil) throws {
    guard schemaVersion == 1, catalogVersion > 0, collections.count <= 200,
      assets.count <= 2000, Set(collections.map(\.id)).count == collections.count,
      Set(assets.map(\.id)).count == assets.count
    else { throw DownloadError.invalidCatalog }
    var hashes: [String: Asset] = [:]
    for asset in assets {
      let suffix = asset.codec == "aac-lc" ? "m4a" : "caf"
      guard Self.safeID(asset.id), ["music", "ambience"].contains(asset.kind),
        asset.byteLength > 0, asset.byteLength <= 100_000_000,
        asset.duration.isFinite, asset.duration > 0,
        ["aac-lc", "pcm_s16le"].contains(asset.codec),
        asset.sha256.count == 64,
        asset.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
        asset.path == "audio/\(asset.sha256).\(suffix)",
        !asset.title.isEmpty, !asset.creator.isEmpty, !asset.attribution.isEmpty,
        Catalog.isHTTPS(asset.originalSourceURL),
        asset.creatorProfileURL.map(Catalog.isHTTPS) ?? true,
        Self.validLicense(asset), bundled?.asset(asset.id) == nil
      else { throw DownloadError.invalidCatalog }
      if let other = hashes[asset.sha256] {
        guard other.byteLength == asset.byteLength, other.codec == asset.codec else {
          throw DownloadError.invalidCatalog
        }
      }
      hashes[asset.sha256] = asset
      if let equivalent = asset.bundledEquivalent {
        guard let original = bundled?.asset(equivalent), original.sha256 == asset.sha256,
          original.byteLength == asset.byteLength, original.codec == asset.codec
        else { throw DownloadError.invalidCatalog }
      }
    }
    let indexed = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
    for collection in collections {
      guard Self.safeID(collection.id), collection.version > 0, !collection.label.isEmpty,
        ["music", "ambience"].contains(collection.kind), !collection.assetIDs.isEmpty,
        Set(collection.assetIDs).count == collection.assetIDs.count,
        collection.totalBytes > 0, collection.totalBytes <= 2_000_000_000,
        collection.kind == "music"
          ? MixSettings.stationIDs.contains(collection.stationID ?? "")
          : collection.stationID == nil
      else { throw DownloadError.invalidCatalog }
      var total = 0
      for id in collection.assetIDs {
        guard let asset = indexed[id], asset.kind == collection.kind else {
          throw DownloadError.invalidCatalog
        }
        total += asset.byteLength
      }
      guard total == collection.totalBytes else { throw DownloadError.invalidCatalog }
    }
  }

  static func safeID(_ id: String) -> Bool {
    !id.isEmpty && id.utf8.count <= 80
      && id.allSatisfy { "abcdefghijklmnopqrstuvwxyz0123456789-".contains($0) }
  }

  private static func validLicense(_ asset: Asset) -> Bool {
    if asset.license == "CC0" {
      return asset.licenseVersion == "1.0"
        && asset.licenseURL.absoluteString == "https://creativecommons.org/publicdomain/zero/1.0/"
    }
    return asset.license == "CC BY"
      && ["1.0", "2.0", "2.5", "3.0", "4.0"].contains(asset.licenseVersion)
      && asset.licenseURL.absoluteString
        == "https://creativecommons.org/licenses/by/\(asset.licenseVersion)/"
  }
}

enum DownloadError: Error {
  case invalidCatalog, libraryReadOnly, unavailableAudio, fileInUse, downloadsDisabled
  case invalidAudio(String)
}
