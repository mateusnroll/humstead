import Foundation
import Testing

struct DownloadCatalogTests {
  @Test func boundsAndReferences() throws {
    let valid = try Self.fixture()
    let catalog = try DownloadCatalog.decode(valid)
    #expect(catalog.collections.count == 1)
    #expect(catalog.assets.count == 1)
    for change in ["traversal", "foreign", "hash", "length", "reference", "station", "schema"] {
      #expect(throws: (any Error).self) { try DownloadCatalog.decode(Self.fixture(change)) }
    }
    #expect(throws: (any Error).self) {
      try DownloadCatalog.decode(Data(repeating: 32, count: 2_000_001))
    }
  }

  @Test func licenseAndOfflineCredits() throws {
    let decoded = try DownloadCatalog.decode(Self.fixture())
    let offline = try DownloadCatalog.decode(JSONEncoder().encode(decoded))
    #expect(offline.assets[0].originalSourceURL.absoluteString == "https://example.org/recording")
    #expect(offline.assets[0].creatorProfileURL?.absoluteString == "https://example.org/creator")
    #expect(offline.assets[0].attribution == "Test author — test-only metadata")
    for version in ["1.0", "2.0", "2.5", "3.0", "4.0"] {
      let by = try DownloadCatalog.decode(Self.fixture("by-\(version)"))
      #expect(by.assets[0].licenseVersion == version)
    }
    for change in ["nc", "license-mismatch", "license-version", "source"] {
      #expect(throws: (any Error).self) { try DownloadCatalog.decode(Self.fixture(change)) }
    }
  }

  static func fixture(_ change: String = "") throws -> Data {
    let hash = String(repeating: "a", count: 64)
    var asset: [String: Any] = [
      "id": "optional-song", "kind": "music", "sha256": hash, "byteLength": 123,
      "codec": "aac-lc", "duration": 12, "path": "audio/\(hash).m4a", "title": "Fixture",
      "creator": "Test author", "originalSourceURL": "https://example.org/recording",
      "creatorProfileURL": "https://example.org/creator", "license": "CC0", "licenseVersion": "1.0",
      "licenseURL": "https://creativecommons.org/publicdomain/zero/1.0/",
      "attribution": "Test author — test-only metadata", "modification": "None",
    ]
    var collection: [String: Any] = [
      "id": "optional-mellow", "kind": "music", "version": 1, "label": "More Mellow",
      "stationID": "mellow", "assetIDs": ["optional-song"], "totalBytes": 123,
    ]
    if change == "traversal" { asset["path"] = "audio/../settings.json" }
    if change == "foreign" { asset["path"] = "https://evil.example/audio/\(hash).m4a" }
    if change == "hash" { asset["sha256"] = String(repeating: "A", count: 64) }
    if change == "length" { asset["byteLength"] = 100_000_001 }
    if change == "reference" { collection["assetIDs"] = ["missing"] }
    if change == "station" { collection["stationID"] = "remote-station" }
    if change.hasPrefix("by-") {
      let version = String(change.dropFirst(3))
      asset["license"] = "CC BY"
      asset["licenseVersion"] = version
      asset["licenseURL"] = "https://creativecommons.org/licenses/by/\(version)/"
    }
    if change == "nc" { asset["license"] = "CC BY-NC" }
    if change == "license-mismatch" { asset["licenseURL"] = "https://example.org/license" }
    if change == "license-version" { asset["licenseVersion"] = "99" }
    if change == "source" { asset["originalSourceURL"] = "file:///etc/passwd" }
    return try JSONSerialization.data(withJSONObject: [
      "schemaVersion": change == "schema" ? 2 : 1, "catalogVersion": 1,
      "collections": [collection], "assets": [asset],
    ])
  }
}
