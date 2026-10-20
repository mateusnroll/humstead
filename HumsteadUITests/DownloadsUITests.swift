import Foundation
import XCTest

@MainActor
final class DownloadsUITests: XCTestCase {
  func testConfirmProgressAndUpdate() async throws {
    let fixture = try await UIDownloadFixture.start()
    try await fixture.configure(["chunk_delay": 0.2])
    let app = XCUIApplication()
    app.launchArguments = [
      "--test-settings", "downloads-\(UUID().uuidString)",
      "--test-download-origin", fixture.origin.absoluteString,
    ]
    let initialRequests = try await fixture.audioRequests()
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.windows["Humstead"].buttons["Play"].waitForExistence(timeout: 10))
    app.typeKey(",", modifierFlags: .command)
    let download = app.buttons["Download Extra Mellow"]
    XCTAssertTrue(download.waitForExistence(timeout: 10), app.debugDescription)
    let beforeConfirmation = try await fixture.audioRequests()
    XCTAssertEqual(beforeConfirmation, initialRequests)
    download.click()
    XCTAssertTrue(app.buttons["Confirm download"].waitForExistence(timeout: 5))
    let duringConfirmation = try await fixture.audioRequests()
    XCTAssertEqual(duringConfirmation, initialRequests)
    app.buttons["Cancel"].click()
    download.click()
    app.buttons["Confirm download"].click()
    XCTAssertTrue(app.buttons["Cancel download"].waitForExistence(timeout: 5))
    app.buttons["Cancel download"].click()
    XCTAssertTrue(download.waitForExistence(timeout: 5))
    try await fixture.configure(["chunk_delay": 0])
    download.click()
    app.buttons["Confirm download"].click()
    XCTAssertTrue(app.buttons["Remove Extra Mellow"].waitForExistence(timeout: 20))
    XCTAssertTrue(app.staticTexts["Installed version 1"].exists)
    try await fixture.configure(["version": 2])
    // Admission is intentionally enforced across relaunches; wait for the real manual interval.
    try await Task.sleep(for: .seconds(61))
    app.buttons["Check for updates"].click()
    let update = app.buttons["Update Extra Mellow"]
    XCTAssertTrue(update.waitForExistence(timeout: 10))
    update.click()
    app.buttons["Confirm download"].click()
    XCTAssertTrue(app.staticTexts["Installed version 2"].waitForExistence(timeout: 20))
  }

  func testOfflineRestartAndRemoval() async throws {
    let fixture = try await UIDownloadFixture.start()
    let app = XCUIApplication()
    let name = "offline-downloads-\(UUID().uuidString)"
    app.launchArguments = [
      "--test-settings", name, "--test-download-origin", fixture.origin.absoluteString,
    ]
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.windows["Humstead"].buttons["Play"].waitForExistence(timeout: 10))
    app.typeKey(",", modifierFlags: .command)
    for label in ["Extra Mellow", "Extra Forest"] {
      let button = app.buttons["Download \(label)"]
      XCTAssertTrue(button.waitForExistence(timeout: 10))
      button.click()
      app.buttons["Confirm download"].click()
      XCTAssertTrue(app.buttons["Remove \(label)"].waitForExistence(timeout: 20))
    }
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    app.launchArguments = ["--test-settings", name]
    app.launch()
    let player = app.windows["Humstead"]
    XCTAssertTrue(player.buttons["Play"].waitForExistence(timeout: 10))
    player.sliders["music-volume"].adjust(toNormalizedSliderPosition: 0.03)
    let title = player.staticTexts["track-title"]
    for _ in 0..<5 {
      if title.value as? String == "Snow Drift" { break }
      let previous = title.value as? String ?? ""
      player.buttons["Next track"].click()
      let changed = expectation(
        for: NSPredicate(format: "value != %@", previous), evaluatedWith: title)
      await fulfillment(of: [changed], timeout: 3)
    }
    XCTAssertEqual(title.value as? String, "Snow Drift")
    player.buttons["Play"].click()
    XCTAssertTrue(player.buttons["Pause"].exists)
    player.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -550)
    let forest = player.checkBoxes["ambience-toggle-extra-forest"]
    XCTAssertTrue(forest.exists)
    player.sliders["ambience-volume-extra-forest"].adjust(toNormalizedSliderPosition: 0.03)
    forest.click()
    XCTAssertEqual((forest.value as? NSNumber)?.intValue, 1)
    app.typeKey(",", modifierFlags: .command)
    app.buttons["Remove Extra Mellow"].click()
    app.buttons["Confirm removal"].click()
    XCTAssertTrue(app.buttons["Download Extra Mellow"].waitForExistence(timeout: 5))
    app.buttons["Remove Extra Forest"].click()
    app.buttons["Confirm removal"].click()
    XCTAssertTrue(app.buttons["Download Extra Forest"].waitForExistence(timeout: 5))
    app.typeKey("w", modifierFlags: .command)
    XCTAssertFalse(player.checkBoxes["ambience-toggle-extra-forest"].exists)
    XCTAssertTrue(player.buttons["Pause"].exists)
    XCTAssertNotEqual(title.value as? String, "Snow Drift")
    player.buttons["Pause"].click()
  }
}

private final class UIDownloadFixture {
  let origin = URL(string: "http://127.0.0.1:38476")!
  static func start() async throws -> UIDownloadFixture {
    let fixture = UIDownloadFixture()
    try await fixture.configure(["version": 1, "chunk_delay": 0])
    return fixture
  }
  func configure(_ values: [String: Double]) async throws {
    var request = URLRequest(url: origin.appendingPathComponent("__configure"))
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: values)
    let (_, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw NSError(domain: "HumsteadFixture", code: 1)
    }
  }
  func audioRequests() async throws -> Int {
    let (data, _) = try await URLSession.shared.data(
      from: origin.appendingPathComponent("__journal"))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return (object["requests"] as? [[String: Any]] ?? []).filter {
      ($0["path"] as? String)?.hasPrefix("/audio/") == true
    }.count
  }
}
