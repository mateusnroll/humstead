import XCTest

@MainActor
final class CreditsUITests: XCTestCase {
  func testOfflineNoticesAndLinks() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--test-settings", "CreditsUITests-\(UUID().uuidString)"]
    app.launch()
    app.typeKey(",", modifierFlags: .command)
    let credits = app.windows["Credits"]
    XCTAssertTrue(credits.waitForExistence(timeout: 10))
    XCTAssertTrue(credits.staticTexts["Credits"].exists)
    XCTAssertEqual(credits.links.matching(identifier: "original-source").count, 13)
    XCTAssertEqual(credits.links.matching(identifier: "creator-profile").count, 13)
    XCTAssertTrue(credits.staticTexts["Morning Coffee"].exists)
    XCTAssertTrue(credits.staticTexts["Coffee Shop at the Capucins"].exists)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(app.windows["Humstead"].exists)
    XCTAssertTrue(app.windows["Humstead"].buttons["Play"].exists)
    app.terminate()
  }
}
