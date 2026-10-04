import Foundation
import Testing

private final class LifecycleBundle: NSObject {}
private final class LifecyclePlayer: AudioPlaying {
  var volume: Float = 0
  var currentTime: TimeInterval = 0
  func prepare() -> Bool { true }
  func play() -> Bool { true }
  func pause() {}
  func stop() {}
}

@MainActor
struct LifecycleTests {
  @Test func routeAndSleepPause() async throws {
    let catalog = try Catalog.load(bundle: Bundle(for: LifecycleBundle.self))
    let audio = AudioController(catalog: catalog, factory: { _, _ in LifecyclePlayer() })
    var request: UInt64 = 1
    audio.selectStation("mellow", requestID: request)
    var events: [AudioRouteObserver.Event] = []
    let observer = AudioRouteObserver { event in
      events.append(event)
      request += 1
      audio.setPlaying(false, requestID: request)
    }
    for event in [AudioRouteObserver.Event.routeChanged, .sleep, .wake] {
      request += 1
      audio.setPlaying(true, requestID: request)
      #expect(await audio.snapshot().isPlaying)
      observer.receive(event)
      #expect(await audio.snapshot().isPlaying == false)
    }
    #expect(events == [.routeChanged, .sleep, .wake])
    observer.stop()
    request += 1
    audio.setPlaying(true, requestID: request)
    observer.receive(.routeChanged)
    #expect(events.count == 3)
    #expect(await audio.snapshot().isPlaying)
    audio.stop()
  }
}
