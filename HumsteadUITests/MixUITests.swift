import XCTest

@MainActor
final class MixUITests: XCTestCase {
  func testRememberedMixJourney() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--test-settings", "mix-journey-\(UUID().uuidString)"]
    app.launch()
    let window = app.windows["Humstead"]
    XCTAssertTrue(window.buttons["Play"].waitForExistence(timeout: 10))
    XCTAssertTrue(window.popUpButtons["Ambience preset"].exists, "The mix picker must exist")
    guard window.popUpButtons["Ambience preset"].exists else {
      app.terminate()
      return
    }
    window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -350)
    window.popUpButtons["Ambience preset"].click()
    app.menuItems["Rainy Window"].click()
    let rain = window.checkBoxes["Rain"]
    XCTAssertEqual((rain.value as? NSNumber)?.intValue, 1)
    window.sliders["ambience-volume-rain"].adjust(toNormalizedSliderPosition: 0.6)
    window.popUpButtons["Ambience preset"].click()
    app.menuItems["Forest"].click()
    window.popUpButtons["Ambience preset"].click()
    app.menuItems["Rainy Window"].click()
    XCTAssertEqual((window.sliders["ambience-volume-rain"].value as? NSNumber)?.doubleValue, 0.6)
    window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 1000)
    window.popUpButtons["Station"].click()
    try XCTUnwrap(
      app.menuItems.matching(identifier: "Jazzy").allElementsBoundByIndex.first { $0.isHittable }
    ).click()
    window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -350)
    XCTAssertEqual((rain.value as? NSNumber)?.intValue, 0)
    window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 1000)
    window.popUpButtons["Station"].click()
    try XCTUnwrap(
      app.menuItems.matching(identifier: "Mellow").allElementsBoundByIndex.first { $0.isHittable }
    ).click()
    window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -350)
    XCTAssertEqual((rain.value as? NSNumber)?.intValue, 1)
    XCTAssertEqual((window.sliders["ambience-volume-rain"].value as? NSNumber)?.doubleValue, 0.6)
    window.sliders["music-volume"].adjust(toNormalizedSliderPosition: 0)
    app.typeKey("p", modifierFlags: .command)
    XCTAssertTrue(window.buttons["Pause"].exists)
    app.typeKey("p", modifierFlags: .command)
    window.buttons["Reset ambience"].click()
    XCTAssertEqual((window.sliders["ambience-volume-rain"].value as? NSNumber)?.doubleValue, 0.35)
    window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -400)
    XCTAssertTrue(window.popUpButtons["Sleep timer"].exists)
    window.popUpButtons["Sleep timer"].click()
    app.menuItems["15 minutes"].click()
    XCTAssertTrue(window.buttons["Cancel timer"].exists)
    window.buttons["Cancel timer"].click()
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    app.launch()
    XCTAssertTrue(window.buttons["Play"].waitForExistence(timeout: 10))
    window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -350)
    XCTAssertEqual((rain.value as? NSNumber)?.intValue, 1)
    XCTAssertFalse(window.buttons["Cancel timer"].exists)
    app.terminate()
  }

  func testBackgroundReopenAndQuit() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--test-settings", "background-\(UUID().uuidString)"]
    app.launch()
    let window = app.windows["Humstead"]
    XCTAssertTrue(window.buttons["Play"].waitForExistence(timeout: 10))
    window.buttons["Play"].click()
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(window.waitForNonExistence(timeout: 5))
    let item = app.statusItems.firstMatch
    XCTAssertTrue(item.exists, "Background playback needs a reachable menu-bar control")
    guard item.exists else {
      app.terminate()
      return
    }
    item.click()
    let pause = try XCTUnwrap(
      app.menuItems.matching(identifier: "Pause").allElementsBoundByIndex.first { $0.isHittable })
    pause.click()
    item.click()
    try XCTUnwrap(
      app.menuItems.matching(identifier: "Jazzy").allElementsBoundByIndex.first { $0.isHittable }
    ).click()
    item.click()
    app.menuItems["Show Humstead"].click()
    XCTAssertTrue(window.waitForExistence(timeout: 5))
    XCTAssertTrue(window.buttons["Play"].exists)
    XCTAssertEqual(window.popUpButtons["Station"].value as? String, "Jazzy")
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
  }
}
