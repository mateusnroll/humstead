import XCTest

@MainActor
final class PrivacyUITests: XCTestCase {
  func testDisclosureAndUnavailableBuild() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-settings", "privacy-off-\(UUID().uuidString)"]
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.windows["Humstead"].buttons["Play"].waitForExistence(timeout: 10))
    app.typeKey(",", modifierFlags: .command)
    let privacy = app.radioButtons["Privacy"]
    XCTAssertTrue(privacy.waitForExistence(timeout: 5), app.debugDescription)
    guard privacy.exists else { return }
    privacy.click()
    let toggle = app.checkBoxes["Share weekly usage summaries"]
    XCTAssertTrue(toggle.exists)
    XCTAssertFalse(toggle.isEnabled)
    XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 0)
    XCTAssertTrue(app.staticTexts["Reporting is unavailable in this build."].exists)
  }
  func testOptInReportDisableAndRelaunch() async throws {
    let origin = URL(string: "http://127.0.0.1:38477")!
    try await configure(origin, ["reset": true])
    let app = XCUIApplication()
    app.launchArguments = [
      "--test-settings", "privacy-on-\(UUID().uuidString)", "--test-usage-origin",
      origin.absoluteString, "--test-usage-clock", "YES", "--test-download-origin",
      "http://127.0.0.1:38476",
    ]
    app.launch()
    defer { app.terminate() }
    let player = app.windows["Humstead"]
    XCTAssertTrue(player.buttons["Play"].waitForExistence(timeout: 10), app.debugDescription)
    timer(app, player)
    openPrivacy(app)
    app.buttons["Advance reporting window"].click()
    let preConsentCount = try await requests(origin).count
    XCTAssertEqual(preConsentCount, 0)
    let toggle = app.checkBoxes["Share weekly usage summaries"]
    XCTAssertTrue(toggle.isEnabled)
    toggle.click()
    await waitValue(toggle, 1)
    app.typeKey("w", modifierFlags: .command)
    player.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -350)
    player.popUpButtons["Ambience preset"].click()
    app.menuItems["Rainy Window"].click()
    player.sliders["ambience-volume-rain"].adjust(toNormalizedSliderPosition: 0.03)
    player.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: 400)
    XCTAssertTrue(player.sliders["music-volume"].isHittable)
    player.sliders["music-volume"].adjust(toNormalizedSliderPosition: 0)
    player.sliders["music-volume"].typeKey(.leftArrow, modifierFlags: [])
    player.sliders["music-volume"].typeKey(.leftArrow, modifierFlags: [])
    XCTAssertEqual((player.sliders["music-volume"].value as? NSNumber)?.doubleValue, 0)
    app.typeKey("p", modifierFlags: .command)
    XCTAssertTrue(player.buttons["Pause"].exists)
    timer(app, player)
    app.statusItems.firstMatch.click()
    app.statusItems.firstMatch.menuItems["Pause"].click()
    app.typeKey(",", modifierFlags: .command)
    app.radioButtons["Downloads"].click()
    let download = app.buttons["Download Extra Mellow"]
    XCTAssertTrue(download.waitForExistence(timeout: 10))
    download.click()
    app.buttons["Confirm download"].click()
    XCTAssertTrue(app.buttons["Remove Extra Mellow"].waitForExistence(timeout: 20))
    app.radioButtons["Privacy"].click()
    app.buttons["Advance reporting window"].click()
    var reports = try await waitReports(origin, count: 1)
    let body = try XCTUnwrap(reports.first?["body"] as? [String: Any])
    XCTAssertEqual(Set(body.keys), Set(["api_key", "event", "distinct_id", "properties"]))
    let properties = try XCTUnwrap(body["properties"] as? [String: Any])
    for key in ["usedAmbience", "usedAmbienceOnly", "usedTimer", "usedMenuBar", "usedDownloads"] {
      XCTAssertEqual(properties[key] as? Bool, true, key)
    }
    try await configure(origin, ["delay": 4])
    app.typeKey("w", modifierFlags: .command)
    timer(app, player)
    openPrivacy(app)
    app.buttons["Advance reporting window"].click()
    reports = try await waitReports(origin, count: 2)
    toggle.click()
    await waitValue(toggle, 0)
    app.typeKey("w", modifierFlags: .command)
    timer(app, player)
    openPrivacy(app)
    app.buttons["Advance reporting window"].click()
    try await Task.sleep(for: .seconds(1))
    let disabledCount = try await requests(origin).count
    XCTAssertEqual(disabledCount, reports.count)
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    app.launch()
    XCTAssertTrue(player.buttons["Play"].waitForExistence(timeout: 10), app.debugDescription)
    openPrivacy(app)
    XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 0)
    let restoredCount = try await requests(origin).count
    XCTAssertEqual(restoredCount, 2)
  }
  private func timer(_ app: XCUIApplication, _ player: XCUIElement) {
    player.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -900)
    player.popUpButtons["Sleep timer"].click()
    app.menuItems["15 minutes"].click()
    XCTAssertTrue(player.buttons["Cancel timer"].exists)
    player.buttons["Cancel timer"].click()
  }
  private func openPrivacy(_ app: XCUIApplication) {
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(app.radioButtons["Privacy"].waitForExistence(timeout: 5))
    app.radioButtons["Privacy"].click()
  }
  private func waitValue(_ element: XCUIElement, _ expected: Int) async {
    let condition = expectation(
      for: NSPredicate(format: "value == %d AND enabled == true", expected), evaluatedWith: element)
    await fulfillment(of: [condition], timeout: 5)
  }
  private func configure(_ origin: URL, _ values: [String: any Sendable]) async throws {
    var request = URLRequest(url: origin.appendingPathComponent("__configure"))
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: values)
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
  }
  private func requests(_ origin: URL) async throws -> [[String: Any]] {
    let (data, _) = try await URLSession.shared.data(
      from: origin.appendingPathComponent("__journal"))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return object["requests"] as? [[String: Any]] ?? []
  }
  private func waitReports(_ origin: URL, count: Int) async throws -> [[String: Any]] {
    for _ in 0..<50 {
      let value = try await requests(origin)
      if value.count == count { return value }
      try await Task.sleep(for: .milliseconds(100))
    }
    let value = try await requests(origin)
    XCTAssertEqual(value.count, count)
    return value
  }

}
