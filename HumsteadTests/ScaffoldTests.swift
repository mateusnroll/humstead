import Foundation
import Testing

struct ScaffoldTests {
  @Test func buildMetadata() throws {
    let bundle = try #require(Bundle(identifier: "com.mateusnroll.humstead.tests"))
    #expect(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "0.1.0")
    #expect(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "1")
    #expect(bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String == "13.0")
  }
}
