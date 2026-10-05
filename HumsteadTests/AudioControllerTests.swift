import AVFoundation
import Foundation
import Testing

private final class AudioTestBundle: NSObject {}

private final class FakePlayers: @unchecked Sendable {
  private let lock = NSLock()
  private var callbacks: [@Sendable (Bool) -> Void] = []
  private var count = 0
  let fail: Bool
  init(fail: Bool = false) { self.fail = fail }
  func make(_ asset: Catalog.Asset, completion: @escaping @Sendable (Bool) -> Void) throws
    -> any AudioPlaying
  {
    lock.withLock {
      count += 1
      callbacks.append(completion)
    }
    return FakePlayer(fail: fail)
  }
  var attempts: Int { lock.withLock { count } }
  func complete(_ index: Int, successfully: Bool = true) {
    let callback = lock.withLock { callbacks[index] }
    callback(successfully)
  }
}

private final class FakePlayer: AudioPlaying {
  var volume: Float = 0
  var currentTime: TimeInterval = 12
  let fail: Bool
  init(fail: Bool) { self.fail = fail }
  func prepare() -> Bool { !fail }
  func play() -> Bool { !fail }
  func pause() {}
  func stop() {}
}

struct AudioControllerTests {
  @Test func orderedIntentsAndFailureBound() async throws {
    let catalog = try Catalog.load(bundle: Bundle(for: AudioTestBundle.self))
    let players = FakePlayers()
    let controller = AudioController(catalog: catalog, factory: players.make)
    controller.selectStation("mellow", requestID: 1)
    let initial = await controller.snapshot()
    #expect(initial.trackID != nil)
    controller.setPlaying(true, requestID: 2)
    controller.selectStation("jazzy", requestID: 3)
    controller.next(requestID: 4)
    controller.setPlaying(false, requestID: 5)
    let paused = await controller.snapshot()
    #expect(paused.stationID == "jazzy")
    #expect(paused.trackID != initial.trackID)
    #expect(!paused.isPlaying && !paused.playbackRequested)
    if players.attempts > 0 { players.complete(0) }
    let stale = await controller.snapshot()
    #expect(stale.trackID == paused.trackID)
    #expect(stale.requestID == 5)
    controller.setVolume(0, requestID: 6)
    controller.setPlaying(true, requestID: 7)
    let silent = await controller.snapshot()
    #expect(silent.playbackRequested && !silent.isPlaying)
    #expect(silent.trackID == paused.trackID)
    controller.setVolume(0.5, requestID: 8)
    #expect(await controller.snapshot().isPlaying)
    controller.setPlaying(false, requestID: 9)
    controller.setVolume(0.8, requestID: 10)
    #expect(await controller.snapshot().isPlaying == false)
    let failingPlayers = FakePlayers(fail: true)
    let failing = AudioController(catalog: catalog, factory: failingPlayers.make)
    failing.selectStation("mellow", requestID: 1)
    let failed = await failing.snapshot()
    #expect(failingPlayers.attempts == 3)
    #expect(failed.error != nil)
    #expect(!failed.playbackRequested)
  }
}

extension AudioControllerTests {
  @Test func realPlayerCompletionAdvancesContinuously() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("silence.caf")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410))
    buffer.frameLength = 4410
    buffer.floatChannelData?[0].initialize(repeating: 0, count: 4410)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    let catalog = try Catalog.load(bundle: Bundle(for: AudioTestBundle.self))
    let controller = AudioController(
      catalog: catalog,
      factory: { _, completion in
        try NativeAudioPlayer(url: url, completion: completion)
      })
    controller.selectStation("mellow", requestID: 1)
    controller.setPlaying(true, requestID: 2)
    let initial = await controller.snapshot()
    #expect(initial.isPlaying)
    var last = initial
    for _ in 0..<100 {
      try await Task.sleep(for: .milliseconds(25))
      last = await controller.snapshot()
      if last.sequence >= initial.sequence + 4 { break }
    }
    #expect(last.sequence >= initial.sequence + 4)
    #expect(last.isPlaying && last.playbackRequested)
    controller.stop()
    #expect(await controller.snapshot().isPlaying == false)
  }
}
