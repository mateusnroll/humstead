import Foundation

struct ShuffleBag {
  private var tracks: [String]
  private let shuffle: ([String]) -> [String]
  private var remaining: [String] = []
  private var previous: String?

  init(tracks: [String], shuffle: @escaping ([String]) -> [String] = { $0.shuffled() }) {
    self.tracks = tracks
    self.shuffle = shuffle
  }

  mutating func replaceTracks(_ tracks: [String]) {
    guard self.tracks != tracks else { return }
    self.tracks = tracks
    remaining = []
  }

  mutating func next() -> String? {
    if remaining.isEmpty {
      remaining = shuffle(tracks)
      if remaining.count > 1, remaining.last == previous {
        remaining.swapAt(0, remaining.count - 1)
      }
    }
    let next = remaining.popLast()
    previous = next
    return next
  }
}
