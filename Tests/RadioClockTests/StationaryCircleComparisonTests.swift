import Testing

@testable import RadioClockLogic

@Test("Stationary AA comparison holds each of its 48 steps for three seconds")
func stationaryCircleComparisonSequence() {
  let algorithms: [CircleBenchmark] = [.analytical, .refinedChord, .singleChord, .tangent]
  let offsets = [(0, 0), (1, 1), (2, 2), (1, 3)]
  let radii = [12, 24, 32]
  #expect(StationaryCircleComparison.count == 48)
  for step in 0..<48 {
    let start = UInt64(step) * 3_000_000
    let (x, y) = offsets[step / 4 % 4]
    for time in [start, start + 1_500_000, start + 2_999_999, start + 144_000_000] {
      let frame = StationaryCircleComparison(elapsedUs: time)
      #expect(frame.index == step)
      #expect(frame.workload == algorithms[step % 4])
      #expect(frame.radius == radii[step / 16])
      #expect(frame.offsets.x == x && frame.offsets.y == y)
      #expect(frame.centre == DrawingPoint(x: 32 + Float(x) / 4, y: 32 + Float(y) / 4))
    }
  }
  #expect(StationaryCircleComparison(elapsedUs: 143_999_999).index == 47)
  #expect(StationaryCircleComparison(elapsedUs: 144_000_000).index == 0)
}

@Test("Stationary AA frames match each coverage algorithm and leave no residue on wraparound")
func stationaryCircleComparisonFrames() throws {
  let black: UInt32 = 0xff00_0000
  var pixels = Array(repeating: UInt32(0x1234_5678), count: 4096)
  var clippedRight = false
  var clippedBottom = false
  var changedAcrossAlgorithms = false
  var previous = pixels
  for step in 0...48 {
    let frame = StationaryCircleComparison(elapsedUs: UInt64(step) * 3_000_000)
    try pixels.withUnsafeMutableBufferPointer { buffer in
      var context = try #require(
        DrawingContext(framebuffer: buffer, contextSize: PixelSize(width: 64, height: 64), pixelFormat: .bgrx8888))
      #expect(frame.paint(into: &context))
    }
    let radius = Float(frame.radius)
    let centre = frame.centre
    for y in 0..<64 {
      for x in 0..<64 {
        let pixel = PixelPoint(x: x, y: y)
        let coverage: Float
        switch frame.workload {
        case .analytical:
          coverage = analyticalDiskCoverage(at: pixel, centre: centre, radius: radius)
        case .refinedChord:
          coverage = diskCoverage(at: pixel, centre: centre, radius: radius)
        case .singleChord, .tangent:
          coverage =
            FiveWayCircleComparison.linearCoverage(
              at: pixel, centre: centre, radius: radius, tangent: frame.workload == .tangent)
            ?? analyticalDiskCoverage(at: pixel, centre: centre, radius: radius)
        default:
          Issue.record("Unexpected stationary comparison workload")
          return
        }
        #expect(pixels[y * 64 + x] == black | UInt32(coverage.unitQuantized8))
      }
    }
    if frame.radius == 32 {
      clippedRight = clippedRight || pixels[32 * 64 + 63] != black
      clippedBottom = clippedBottom || pixels[63 * 64 + 32] != black
    }
    if step % 4 != 0, pixels != previous { changedAcrossAlgorithms = true }
    previous = pixels
  }
  #expect(clippedRight && clippedBottom && changedAcrossAlgorithms)
  #expect(pixels[32 * 64 + 63] == black && pixels[63 * 64 + 32] == black)
}
