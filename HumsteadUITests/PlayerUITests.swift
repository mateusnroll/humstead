import XCTest

@MainActor
final class PlayerUITests: XCTestCase {
  func testStationPlaybackControls() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--test-settings", "PlayerUITests-\(UUID().uuidString)"]
    app.launch()
    let window = app.windows["Humstead"]
    XCTAssertTrue(window.buttons["Play"].waitForExistence(timeout: 10))
    XCTAssertTrue(window.buttons["Next track"].exists)
    XCTAssertTrue(window.sliders["music-volume"].exists)
    window.buttons["Play"].click()
    XCTAssertTrue(window.buttons["Pause"].waitForExistence(timeout: 5))
    window.buttons["Pause"].click()
    XCTAssertTrue(window.buttons["Play"].waitForExistence(timeout: 5))
    let title = (window.staticTexts["track-title"].value as? String ?? "")
    window.buttons["Next track"].click()
    XCTAssertTrue(window.buttons["Play"].exists)
    let changed = NSPredicate(format: "value != %@", title)
    expectation(for: changed, evaluatedWith: window.staticTexts["track-title"])
    waitForExpectations(timeout: 5)
    app.terminate()
  }

  func testOfflineStationJourney() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--test-settings", "PlayerUITests-\(UUID().uuidString)"]
    app.launch()
    let window = app.windows["Humstead"]
    XCTAssertTrue(window.buttons["Play"].waitForExistence(timeout: 10))
    let titles: [String: Set<String>] = [
      "Mellow": ["Morning Coffee", "A Little Shade", "Creature Comforts"],
      "Jazzy": ["Keeping Cool", "Chills", "Everything You Ever Dreamed"],
      "Late Night": ["Foggy Headed", "Snow Drift", "2 Hour Delay"],
    ]
    let slider = window.sliders["music-volume"]
    for station in ["Mellow", "Jazzy", "Late Night"] {
      window.popUpButtons["Station"].click()
      let choice = try XCTUnwrap(
        app.menuItems.matching(identifier: station).allElementsBoundByIndex.first { $0.isHittable })
      choice.click()
      let prepared = NSPredicate { _, _ in
        titles[station]!.contains(window.staticTexts["track-title"].value as? String ?? "")
      }
      XCTAssertTrue(
        XCTWaiter.wait(
          for: [XCTNSPredicateExpectation(predicate: prepared, object: nil)], timeout: 5)
          == .completed)
      assertStatus("Ready when you are", in: window)
      window.buttons["Play"].click()
      assertStatus("Playing from your Mac", in: window)
      let beforeNext = window.staticTexts["track-title"].value as? String ?? ""
      window.buttons["Next track"].click()
      let advanced = NSPredicate(format: "value != %@", beforeNext)
      XCTAssertTrue(
        XCTWaiter.wait(
          for: [
            XCTNSPredicateExpectation(
              predicate: advanced, object: window.staticTexts["track-title"])
          ], timeout: 5) == .completed)
      assertStatus("Playing from your Mac", in: window)
      slider.adjust(toNormalizedSliderPosition: 0)
      assertStatus("Music is muted", in: window)
      let mutedTrack = window.staticTexts["track-title"].value as? String
      slider.adjust(toNormalizedSliderPosition: 0.4)
      assertStatus("Playing from your Mac", in: window)
      XCTAssertEqual(window.staticTexts["track-title"].value as? String, mutedTrack)
      window.buttons["Pause"].click()
      assertStatus("Ready when you are", in: window)
      slider.adjust(toNormalizedSliderPosition: 0.65)
      assertStatus("Ready when you are", in: window)
    }
    app.terminate()
  }
  func testMinimumWindowLayout() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--test-settings", "PlayerUITests-\(UUID().uuidString)"]
    app.launch()
    let window = app.windows["Humstead"]
    XCTAssertTrue(window.buttons["Play"].waitForExistence(timeout: 10))
    print("Original window frame: \(window.frame)")
    let right = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(
      CGVector(dx: 1, dy: 0))
    right.press(forDuration: 0.2, thenDragTo: right.withOffset(CGVector(dx: -300, dy: 0)))
    let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(
      CGVector(dx: 0, dy: 1))
    bottom.press(forDuration: 0.2, thenDragTo: bottom.withOffset(CGVector(dx: 0, dy: -300)))
    print("Minimum window frame: \(window.frame)")
    XCTAssertLessThanOrEqual(window.frame.width, 330)
    XCTAssertLessThanOrEqual(window.frame.height, 480)
    XCTAssertTrue(window.popUpButtons["Station"].isHittable)
    XCTAssertTrue(window.buttons["Play"].isHittable)
    XCTAssertTrue(window.buttons["Next track"].isHittable)
    window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300)
    XCTAssertTrue(window.sliders["music-volume"].isHittable)
    let capture = XCTAttachment(screenshot: window.screenshot())
    capture.name = "Minimum player window"
    capture.lifetime = .keepAlways
    add(capture)
    app.terminate()
  }

  private func assertStatus(_ value: String, in window: XCUIElement) {
    let expected = NSPredicate(format: "value == %@", value)
    XCTAssertTrue(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: expected, object: window.staticTexts["playback-status"])
        ], timeout: 5) == .completed)
  }
}
