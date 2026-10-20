import Foundation
import Testing

struct UsageTransportTests {
  @Test func restrictedRequests() async throws {
    let fixture = try await AnalyticsFixture.start()
    defer { fixture.stop() }
    let transport = UsageTransport(
      configuration: UsageConfiguration(
        endpoint: fixture.origin.appendingPathComponent("i/v0/e"), token: "humstead-local-test",
        version: "0.1"))
    let data = Data("{\"event\":\"fixture\"}".utf8)
    await withCheckedContinuation { done in transport.send(data) { done.resume() } }
    var requests = try await fixture.requests()
    #expect(requests.count == 1)
    let first = try #require(requests.first)
    #expect(first["method"] as? String == "POST")
    let headers = try #require(first["headers"] as? [String: String])
    #expect(headers["User-Agent"] == "Humstead")
    #expect(headers["Content-Type"] == "application/json")
    #expect(headers["Cookie"] == nil)
    #expect(headers["Authorization"] == nil)
    for configuration: [String: any Sendable] in [
      ["status": 302], ["status": 500], ["status": 200, "oversize": true],
    ] {
      try await fixture.configure(configuration)
      await withCheckedContinuation { done in transport.send(data) { done.resume() } }
    }
    requests = try await fixture.requests()
    #expect(requests.count == 4)
    #expect(requests.allSatisfy { $0["path"] as? String == "/i/v0/e" })
    #expect(requests.allSatisfy { ($0["headers"] as? [String: String])?["Cookie"] == nil })
    try await fixture.configure(["status": 200, "oversize": false, "delay": 8])
    let start = ContinuousClock.now
    await withCheckedContinuation { done in transport.send(data) { done.resume() } }
    #expect(start.duration(to: .now) >= .seconds(4))
    #expect(start.duration(to: .now) < .seconds(7))
    let cancelStart = ContinuousClock.now
    await withCheckedContinuation { done in
      transport.send(data) { done.resume() }
      transport.cancel()
    }
    #expect(cancelStart.duration(to: .now) < .seconds(1))
  }
}

final class AnalyticsFixture: @unchecked Sendable {
  let process: Process
  let directory: URL
  let origin: URL
  let terminated: DispatchSemaphore
  init(process: Process, directory: URL, origin: URL, terminated: DispatchSemaphore) {
    self.process = process
    self.directory = directory
    self.origin = origin
    self.terminated = terminated
  }
  static func start() async throws -> AnalyticsFixture {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let ready = directory.appendingPathComponent("ready.json")
    let process = Process()
    let terminated = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in terminated.signal() }
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [
      root.appendingPathComponent("scripts/analytics-fixture.py").path, "--ready", ready.path,
    ]
    try process.run()
    for _ in 0..<100 {
      if let data = try? Data(contentsOf: ready),
        let object = try? JSONDecoder().decode([String: String].self, from: data),
        let text = object["origin"], let origin = URL(string: text)
      {
        return AnalyticsFixture(
          process: process, directory: directory, origin: origin, terminated: terminated)
      }
      try await Task.sleep(for: .milliseconds(50))
    }
    process.terminate()
    throw NSError(domain: "AnalyticsFixture", code: 1)
  }
  func configure(_ values: [String: any Sendable]) async throws {
    var request = URLRequest(url: origin.appendingPathComponent("__configure"))
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: values)
    let (_, response) = try await URLSession.shared.data(for: request)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
  }
  func requests() async throws -> [[String: Any]] {
    let (data, _) = try await URLSession.shared.data(
      from: origin.appendingPathComponent("__journal"))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return object["requests"] as? [[String: Any]] ?? []
  }
  func stop() {
    if process.isRunning { process.terminate() }
    if terminated.wait(timeout: .now() + 5) != .success {
      Issue.record("Analytics fixture did not stop within five seconds.")
    }
    try? FileManager.default.removeItem(at: directory)
  }
}
