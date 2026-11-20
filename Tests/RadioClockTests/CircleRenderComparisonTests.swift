import Testing

@testable import RadioClockLogic

private struct ComparisonRecorder: CoverageSpanRasterTarget {
  let contextSize = PixelSize(width: 64, height: 64)
  var pixels = Array(repeating: UInt8(0), count: 4096)
  var visited: Set<Int> = []

  mutating func paintSpan(y: Int, from x: Int, to endX: Int, coverage: UInt8, operation: DrawingOperation) -> Bool {
    record(y: y, x: x, count: endX - x, operation: operation) { _ in coverage }
  }

  mutating func paintSpan(y: Int, from x: Int, coverage: Span<UInt8>, operation: DrawingOperation) -> Bool {
    record(y: y, x: x, count: coverage.count, operation: operation) { coverage[$0] }
  }

  private mutating func record(y: Int, x: Int, count: Int, operation: DrawingOperation, sample: (Int) -> UInt8) -> Bool
  {
    #expect(operation == .fill)
    guard (0..<64).contains(y), x >= 0, count > 0, x + count <= 64, x / 32 == (x + count - 1) / 32 else {
      Issue.record("Comparison emitted a span outside its lane")
      return false
    }
    for offset in 0..<count {
      let index = y * 64 + x + offset
      let inserted = visited.insert(index).inserted
      #expect(inserted)
      pixels[index] = sample(offset)
    }
    return true
  }
}

@Test("Circle comparison records distinct analytical and chord coverage in the two lanes")
func circleComparisonCoverage() {
  let times: [UInt64] = [0, 123_457, 4_400_000, 7_000_000, 9_200_000]
  let origin = CircleRenderComparison.centres(at: 0).analytical
  let moved = CircleRenderComparison.centres(at: times[1]).analytical
  #expect(origin != moved)
  #expect(moved.x.rounded(.down) != moved.x && moved.y.rounded(.down) != moved.y)
  #expect(CircleRenderComparison.radius == 4)
  var distinguishingPixels = 0
  for time in times {
    let (left, right) = CircleRenderComparison.centres(at: time)
    #expect(right.x - left.x == 32 && right.y == left.y)
    var recorder = ComparisonRecorder()
    let completed = CircleRenderComparison.paint(into: &recorder, at: time)
    #expect(completed)
    for y in 0..<64 {
      for x in 0..<32 {
        let analytical = analyticalDiskCoverage(at: PixelPoint(x: x, y: y), centre: left, radius: 4).unitQuantized8
        let chord = diskCoverage(at: PixelPoint(x: x + 32, y: y), centre: right, radius: 4).unitQuantized8
        #expect(recorder.pixels[y * 64 + x] == analytical)
        #expect(recorder.pixels[y * 64 + x + 32] == chord)
        if analytical != chord { distinguishingPixels += 1 }
      }
    }
  }
  #expect(distinguishingPixels > 0)
}
