import Foundation

struct SleepTimer {
  enum Action: Equatable {
    case none
    case fade(UInt64)
    case pause
  }
  private(set) var deadline: Double?
  private(set) var generation: UInt64 = 0
  private(set) var isFading = false
  private(set) var minutes = 0

  mutating func start(minutes: Int, now: Double) {
    guard [15, 30, 60].contains(minutes) else { return }
    cancel()
    self.minutes = minutes
    deadline = now + Double(minutes * 60)
  }
  mutating func cancel() {
    generation += 1
    deadline = nil
    isFading = false
    minutes = 0
  }
  func remaining(now: Double) -> Int { max(0, Int(ceil((deadline ?? now) - now))) }
  mutating func advance(now: Double, playing: Bool) -> Action {
    guard let deadline, now >= deadline, !isFading else { return .none }
    if !playing {
      cancel()
      return .pause
    }
    isFading = true
    return .fade(generation)
  }
  mutating func finish(generation token: UInt64) -> Bool {
    guard token == generation, isFading else { return false }
    cancel()
    return true
  }
}
