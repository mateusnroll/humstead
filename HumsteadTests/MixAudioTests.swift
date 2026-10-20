import AVFoundation
import Foundation
import Testing

private final class MixTestBundle: NSObject {}

struct MixAudioTests {
  @Test func failedLayerWaitsForExplicitReenable() async throws {
    let catalog = try Catalog.load(bundle: Bundle(for: MixTestBundle.self))
    let attempts = LayerStartAttempts()
    let audio = AudioController(catalog: catalog) { asset, _ in
      FailingLayerPlayer(id: asset.id, attempts: attempts)
    }
    audio.selectStation("mellow", requestID: 1)
    var mix = ["rain": AmbienceLevel(enabled: true, level: 0.2)]
    audio.setMix(mix, requestID: 2)
    audio.setPlaying(true, requestID: 3)
    #expect(await audio.snapshot().layerErrors["rain"] != nil)
    #expect(attempts.rain == 1)
    audio.setPlaying(false, requestID: 4)
    audio.setPlaying(true, requestID: 5)
    mix["forest"] = AmbienceLevel(enabled: true, level: 0.2)
    audio.setMix(mix, requestID: 6)
    #expect(await audio.snapshot().activeLayers == ["forest"])
    #expect(attempts.rain == 1)
    mix["rain"]?.enabled = false
    audio.setMix(mix, requestID: 7)
    mix["rain"]?.enabled = true
    audio.setMix(mix, requestID: 8)
    #expect(await audio.snapshot().layerErrors["rain"] != nil)
    #expect(attempts.rain == 2)
    audio.stop()
  }

  @Test func layerLifecycleAndOrdering() async throws {
    let bundle = Bundle(for: MixTestBundle.self)
    let catalog = try Catalog.load(bundle: bundle)
    let controller = AudioController(catalog: catalog) { asset, completion in
      try NativeAudioPlayer(
        url: Catalog.verifiedURL(for: asset, bundle: bundle), completion: completion)
    }
    controller.selectStation("mellow", requestID: 1)
    controller.setMix(
      [
        "rain": AmbienceLevel(enabled: true, level: 0.01),
        "forest": AmbienceLevel(enabled: true, level: 0.01),
      ], requestID: 2)
    controller.setPlaying(true, requestID: 3)
    let initial = await controller.snapshot()
    #expect(initial.activeLayers == Set(["rain", "forest"]))
    #expect(initial.isPlaying)
    controller.next(requestID: 4)
    #expect(await controller.snapshot().activeLayers == initial.activeLayers)
    controller.setVolume(0, requestID: 5)
    let silentMusic = await controller.snapshot()
    #expect(silentMusic.isPlaying)
    controller.setPlaying(false, requestID: 6)
    #expect(await controller.snapshot().isPlaying == false)
    controller.setPlaying(true, requestID: 7)
    #expect(await controller.snapshot().trackID == silentMusic.trackID)
    controller.setMix(
      [
        "rain": AmbienceLevel(enabled: false, level: 0.1),
        "forest": AmbienceLevel(enabled: true, level: 0.02),
      ], requestID: 8)
    #expect(await controller.snapshot().activeLayers == Set(["forest"]))
    controller.setMix([:], requestID: 2)
    #expect(await controller.snapshot().activeLayers == Set(["forest"]))
    let excessive = Dictionary(
      uniqueKeysWithValues: (0..<17).map {
        ("extra-\($0)", AmbienceLevel(enabled: true, level: 0.1))
      })
    controller.setMix(excessive, requestID: 9)
    let bounded = await controller.snapshot()
    #expect(bounded.activeLayers == Set(["forest"]))
    #expect(bounded.error?.contains("16") == true)
    controller.setMix(
      [
        "forest": AmbienceLevel(enabled: true, level: 0.02),
        "missing": AmbienceLevel(enabled: true, level: 0.1),
      ], requestID: 10)
    let partial = await controller.snapshot()
    #expect(partial.activeLayers == Set(["forest"]))
    #expect(partial.layerErrors["missing"] != nil)
    controller.stop()
    #expect(await controller.snapshot().isPlaying == false)
  }
}

private final class LayerStartAttempts: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  func recordRain() { lock.withLock { count += 1 } }
  var rain: Int { lock.withLock { count } }
}

private final class FailingLayerPlayer: AudioPlaying {
  let id: String
  let attempts: LayerStartAttempts
  init(id: String, attempts: LayerStartAttempts) {
    self.id = id
    self.attempts = attempts
  }
  var volume: Float = 0
  var currentTime: TimeInterval { 0 }
  func prepare() -> Bool { true }
  func play() -> Bool {
    if id == "rain" {
      attempts.recordRain()
      return false
    }
    return true
  }
  func pause() {}
  func stop() {}
}
