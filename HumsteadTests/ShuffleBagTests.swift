import Testing

struct ShuffleBagTests {
  @Test func coverageAndBoundary() {
    var bag = ShuffleBag(tracks: ["a", "b", "c"], shuffle: { $0.reversed() })
    var previous: String?
    for _ in 0..<20 {
      var cycle: Set<String> = []
      for _ in 0..<3 {
        let next = bag.next()
        #expect(next != previous)
        if let next { cycle.insert(next) }
        previous = next
      }
      #expect(cycle == ["a", "b", "c"])
    }
    var empty = ShuffleBag(tracks: [])
    #expect(empty.next() == nil)
    var single = ShuffleBag(tracks: ["a"])
    #expect(single.next() == "a")
    #expect(single.next() == "a")
  }
}
