import XCTest

@MainActor
final class ScaffoldUITests: XCTestCase {
  func testVisibleWindowLifecycle() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    let window = app.windows["Humstead"]
    XCTAssertTrue(window.waitForExistence(timeout: 10))
    XCTAssertTrue(window.staticTexts["humstead-heading"].exists)
    XCTAssertTrue(
      window.staticTexts["A quiet place for music and ambience. Player in development."].exists)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(window.waitForNonExistence(timeout: 5))
    app.activate()
    XCTAssertTrue(window.waitForExistence(timeout: 5))
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
  }
}
