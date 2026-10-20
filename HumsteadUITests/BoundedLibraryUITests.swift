import XCTest

@MainActor
final class BoundedLibraryUITests: XCTestCase {
  func testMaximumLibraryRemainsReachable() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    var build = Bundle(for: Self.self).bundleURL
    for _ in 0..<8 { build.deleteLastPathComponent() }
    let fixtureURL = build.appendingPathComponent("bounded-library-state.json")
    let fixture = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: String],
      "Prepare the external fixture with scripts/verify --prepare-bounded-library")
    let name = try XCTUnwrap(fixture["name"])
    app.launchArguments = ["--test-settings", name, "-AppleKeyboardUIMode", "3"]
    defer { app.terminate() }
    let start = Date()
    app.launch()
    let player = app.windows["Humstead"]
    XCTAssertTrue(player.buttons["Play"].waitForExistence(timeout: 2), app.debugDescription)
    XCTAssertTrue(player.buttons["Play"].isEnabled)
    print(
      "Maximum-library launch through XCTest ready observation: \(Date().timeIntervalSince(start)) seconds"
    )
    XCTAssertEqual(
      (player.sliders["music-volume"].value as? NSNumber)?.doubleValue ?? -1, 0.03, accuracy: 0.001,
      app.debugDescription)
    let scroll = player.scrollViews.firstMatch
    for index in [1999, 0, 1000] {
      if index != 1999 {
        app.terminate()
        app.launch()
      }
      let id = String(format: "workload-%04d", index)
      let toggle = player.checkBoxes["ambience-toggle-\(id)"]
      if index > 0 { scroll.scroll(byDeltaX: 0, deltaY: CGFloat(-index * 66)) }
      try reveal(index, in: player, scroll: scroll)
      XCTAssertTrue(toggle.isHittable)
      if index == 0 {
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 1)
      } else {
        toggle.click()
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 0)
        let message = player.staticTexts["ambience-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 3))
        XCTAssertFalse(message.frame.isEmpty)
        XCTAssertTrue(player.frame.contains(message.frame))
      }
      let slider = player.sliders["ambience-volume-\(id)"]
      XCTAssertTrue(slider.exists)
      if !slider.isHittable { scroll.scroll(byDeltaX: 0, deltaY: -100) }
      XCTAssertTrue(slider.isHittable)
      slider.adjust(toNormalizedSliderPosition: 0.5)
      let before = try XCTUnwrap((slider.value as? NSNumber)?.doubleValue)
      app.typeKey(.rightArrow, modifierFlags: [])
      let after = try XCTUnwrap((slider.value as? NSNumber)?.doubleValue)
      XCTAssertGreaterThan(after, before)
      XCTAssertEqual(player.popUpButtons["Station"].value as? String, "Mellow")
      XCTAssertTrue(slider.isHittable)
    }
    app.typeKey(",", modifierFlags: .command)
    let downloads = app.radioButtons["Downloads"]
    XCTAssertTrue(downloads.waitForExistence(timeout: 5))
    downloads.click()
    XCTAssertTrue(app.buttons["Remove Collection 000"].waitForExistence(timeout: 5))
    let settingsScroll = app.windows.element(matching: .window, identifier: "Settings")
      .scrollViews.firstMatch
    let actualScroll = settingsScroll.exists ? settingsScroll : app.scrollViews.firstMatch
    actualScroll.scroll(byDeltaX: 0, deltaY: -100_000)
    XCTAssertTrue(app.buttons["Remove Collection 199"].waitForExistence(timeout: 5))
    app.radioButtons["Credits"].click()
    app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -1_000_000)
    XCTAssertTrue(app.staticTexts["Workload Forest 1999"].waitForExistence(timeout: 5))
  }

  func testSettingsKeyboardCrossesLazyBoundaries() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    var build = Bundle(for: Self.self).bundleURL
    for _ in 0..<8 { build.deleteLastPathComponent() }
    let fixture = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: Data(contentsOf: build.appendingPathComponent("bounded-library-state.json")))
        as? [String: String])
    app.launchArguments = ["--test-settings", try XCTUnwrap(fixture["name"])]
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
    app.typeKey(",", modifierFlags: .command)
    app.radioButtons["Downloads"].click()
    XCTAssertTrue(app.buttons["Remove Collection 000"].waitForExistence(timeout: 5))
    // Updates, then collection 000, then ten further collection controls.
    for _ in 0..<12 { app.typeKey(.tab, modifierFlags: []) }
    let collection = app.buttons["Remove Collection 010"]
    XCTAssertTrue(collection.waitForExistence(timeout: 3))
    XCTAssertTrue(collection.isHittable)
    app.typeKey(.space, modifierFlags: [])
    XCTAssertTrue(app.staticTexts["Remove Collection 010?"].waitForExistence(timeout: 3))
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(collection.isHittable)
    app.typeKey(.tab, modifierFlags: .shift)
    app.typeKey(.space, modifierFlags: [])
    XCTAssertTrue(app.staticTexts["Remove Collection 009?"].waitForExistence(timeout: 3))
    app.typeKey(.escape, modifierFlags: [])
    app.radioButtons["Credits"].click()
    // Thirteen bundled credits have three links each; continue into downloaded credits.
    for _ in 0..<42 { app.typeKey(.tab, modifierFlags: []) }
    let license = app.links["credit-license-workload-0000"]
    XCTAssertTrue(license.waitForExistence(timeout: 3))
    XCTAssertTrue(license.isHittable)
    for _ in 0..<6 { app.typeKey(.tab, modifierFlags: []) }
    XCTAssertTrue(app.links["credit-license-workload-0002"].isHittable)
  }

  private func reveal(_ index: Int, in player: XCUIElement, scroll: XCUIElement) throws {
    let target = player.checkBoxes[String(format: "ambience-toggle-workload-%04d", index)]
    for _ in 0..<30 {
      if target.exists && target.isHittable { return }
      let visible = player.checkBoxes.allElementsBoundByIndex.filter { $0.isHittable }
        .compactMap { element -> Int? in
          let prefix = "ambience-toggle-workload-"
          guard element.identifier.hasPrefix(prefix) else { return nil }
          return Int(element.identifier.dropFirst(prefix.count))
        }
      let distance = visible.first.map { (index - $0) * 64 } ?? 500
      let delta = max(-10_000, min(10_000, distance))
      scroll.scroll(byDeltaX: 0, deltaY: CGFloat(delta == 0 ? -100 : -delta))
    }
    XCTFail("Could not reach optional ambience \(index)")
  }

}
