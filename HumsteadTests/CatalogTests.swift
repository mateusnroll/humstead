import AVFoundation
import CryptoKit
import Foundation
import Testing

private final class CatalogBundleLocator: NSObject {}

struct CatalogTests {
  @Test func bundledAssetsMatchProvenance() throws {
    let bundle = Bundle(for: CatalogBundleLocator.self)
    let catalogURL = try #require(bundle.url(forResource: "catalog", withExtension: "json"))
    let data = try Data(contentsOf: catalogURL)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let assets = try #require(root["assets"] as? [[String: Any]])
    #expect(assets.count == 13)
    let provenanceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("docs/audio/manifest.json")
    let provenance = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: provenanceURL)) as? [[String: Any]])
    #expect(provenance.count == 13)
    for asset in assets {
      let record = try #require(provenance.first { $0["id"] as? String == asset["id"] as? String })
      #expect(record["derivedSHA256"] as? String == asset["sha256"] as? String)
      for key in ["originalSHA256", "licenseEvidenceSHA256"] {
        let digest = try #require(record[key] as? String)
        #expect(digest.count == 64 && digest.allSatisfy { $0.isHexDigit })
      }
      let name = try #require(asset["resource"] as? String)
      let url = try #require(bundle.url(forResource: name, withExtension: nil))
      let bytes = try Data(contentsOf: url)
      #expect(bytes.count == asset["byteLength"] as? Int)
      let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
      #expect(hash == asset["sha256"] as? String)
      #expect(asset["license"] as? String == "CC0-1.0")
      for key in ["sourceURL", "profileURL", "licenseURL"] {
        let link = try #require(asset[key] as? String)
        #expect(URL(string: link)?.scheme == "https")
      }
      let player = try AVAudioPlayer(contentsOf: url)
      #expect(player.prepareToPlay())
      let duration = try #require(asset["duration"] as? Double)
      #expect(abs(player.duration - duration) < 0.2)
      #expect(player.duration > 20)
    }
  }
}
