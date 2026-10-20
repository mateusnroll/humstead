import Foundation
import Testing

struct SleepTimerTests {
  @Test func expiryPauseCancelAndReplacement() {
    var timer = SleepTimer()
    #expect(timer.deadline == nil)
    timer.start(minutes: 15, now: 10)
    let old = timer.generation
    #expect(timer.advance(now: 909, playing: true) == .none)
    #expect(timer.advance(now: 910, playing: true) == .fade(old))
    timer.cancel()
    let staleFinished = timer.finish(generation: old)
    #expect(!staleFinished)
    timer.start(minutes: 30, now: 1000)
    #expect(timer.advance(now: 2800, playing: false) == .pause)
    #expect(timer.deadline == nil)
    timer.start(minutes: 15, now: 3000)
    timer.start(minutes: 60, now: 3001)
    #expect(timer.advance(now: 3901, playing: true) == .none)
    #expect(timer.remaining(now: 3002) == 3599)
  }
}

private final class TimerBundle: NSObject {}
private final class GainProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: Float] = [:]
  func set(_ id: String, _ value: Float) { lock.withLock { values[id] = value } }
  func get(_ id: String) -> Float { lock.withLock { values[id] ?? -1 } }
}
private final class GainPlayer: AudioPlaying {
  let id: String
  let probe: GainProbe
  init(id: String, probe: GainProbe) {
    self.id = id
    self.probe = probe
  }
  var volume: Float {
    get { probe.get(id) }
    set { probe.set(id, newValue) }
  }
  var currentTime: TimeInterval { 5 }
  func prepare() -> Bool { true }
  func play() -> Bool { true }
  func pause() {}
  func stop() {}
}

extension SleepTimerTests {
  @Test func fadePreservesLevelsAndCancellation() async throws {
    let catalog = try Catalog.load(bundle: Bundle(for: TimerBundle.self))
    let probe = GainProbe()
    let audio = AudioController(
      catalog: catalog, factory: { asset, _ in GainPlayer(id: asset.id, probe: probe) })
    audio.selectStation("mellow", requestID: 1)
    audio.setMix(["rain": AmbienceLevel(enabled: true, level: 0.4)], requestID: 2)
    audio.setPlaying(true, requestID: 3)
    audio.fadeOut(timerID: 10, requestID: 4)
    try await Task.sleep(for: .milliseconds(300))
    #expect(probe.get("rain") < 0.4)
    audio.cancelFade(requestID: 5)
    let cancelled = await audio.snapshot()
    #expect(cancelled.isPlaying)
    #expect(probe.get("rain") == 0.4)
    audio.fadeOut(timerID: 11, requestID: 6)
    audio.setVolume(0.3, requestID: 7)
    try await Task.sleep(for: .milliseconds(5300))
    let expired = await audio.snapshot()
    #expect(!expired.isPlaying && !expired.playbackRequested)
    #expect(expired.expiredTimer == 11)
    #expect(expired.volume == 0.3)
    #expect(expired.mix["rain"]?.level == 0.4)
    #expect(probe.get("rain") == 0.4)
    audio.setPlaying(true, requestID: 8)
    #expect(await audio.snapshot().isPlaying)
    audio.stop()
  }
}
