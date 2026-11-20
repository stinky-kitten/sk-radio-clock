import Testing

@testable import RadioClockLogic

@Test("Five-way comparison holds each quarter-pixel offset for ten seconds and repeats")
func fiveWayCircleStationaryPositions() {
  let interval: UInt64 = 10_000_000
  for index in 0..<16 {
    let start = UInt64(index) * interval
    let expected = DrawingPoint(x: 10 + Float(index % 4) / 4, y: 15 + Float(index / 4) / 4)
    for elapsed in [start, start + interval / 2, start + interval - 1] {
      #expect(FiveWayCircleComparison.positionIndex(at: elapsed) == index)
      #expect(FiveWayCircleComparison.localCentre(at: elapsed) == expected)
    }
  }
  #expect(FiveWayCircleComparison.positionIndex(at: 16 * interval) == 0)
  #expect(FiveWayCircleComparison.localCentre(at: 16 * interval) == DrawingPoint(x: 10, y: 15))
}

@Test("Five-way circle frames match each lane's algorithm and stay within their regions")
func fiveWayCircleFrame() throws {
  let size = PixelSize(width: 64, height: 64)
  let black: UInt32 = 0xff00_0000
  var distinctions: Set<Int> = []
  for index in 0..<16 {
    let time = UInt64(index) * 10_000_000
    let local = FiveWayCircleComparison.localCentre(at: time)
    var frame = Array(repeating: black, count: 4096)
    var counts = FiveWayCircleComparison.Fallbacks()
    try frame.withUnsafeMutableBufferPointer { buffer in
      var context = try #require(DrawingContext(framebuffer: buffer, contextSize: size, pixelFormat: .bgrx8888))
      context.fillColor = .blue
      let completed = FiveWayCircleComparison.paint(into: &context, at: time, fallbacks: &counts)
      #expect(completed)
    }
    var expectedFallbacks = FiveWayCircleComparison.Fallbacks()
    for lane in 0..<6 {
      let left = lane % 3 * 21
      let top = lane / 3 * 32
      let centre = DrawingPoint(x: local.x + Float(left), y: local.y + Float(top))
      #expect(centre.x - Float(left) == local.x && centre.y - Float(top) == local.y)
      var hasInk = false
      for y in top..<(top + 32) {
        for x in left..<(lane % 3 == 2 ? 64 : left + 21) {
          let pixel = PixelPoint(x: x, y: y)
          let exact = analyticalDiskCoverage(at: pixel, centre: centre, radius: 4)
          let expected: Float
          switch lane {
          case 0: expected = exact
          case 1: expected = diskCoverage(at: pixel, centre: centre, radius: 4)
          case 2, 3:
            if let linear = FiveWayCircleComparison.linearCoverage(
              at: pixel, centre: centre, radius: 4, tangent: lane == 3)
            {
              expected = linear
            } else {
              if lane == 2 { expectedFallbacks.singleChord += 1 } else { expectedFallbacks.tangent += 1 }
              expected = exact
            }
          case 4:
            let dx = Float(x) + 0.5 - centre.x
            let dy = Float(y) + 0.5 - centre.y
            expected = dx * dx + dy * dy <= 16 ? 1 : 0
          default: expected = 0
          }
          let byte = expected.unitQuantized8
          if byte != 0 { hasInk = true }
          if lane < 5 && byte != exact.unitQuantized8 { distinctions.insert(lane) }
          #expect(frame[y * 64 + x] == black | UInt32(byte))
        }
      }
      #expect(hasInk == (lane < 5))
    }
    #expect(counts.singleChord == expectedFallbacks.singleChord)
    #expect(counts.tangent == expectedFallbacks.tangent)
  }
  #expect(distinctions == [1, 2, 3, 4])
}

@Test("Single chord and tangent face inward and bracket a simple circular cap")
func fiveWayCircleLinearGeometry() throws {
  let centre = DrawingPoint(x: -3.5, y: 0.5)
  let chord = try #require(FiveWayCircleComparison.linearCoverage(at: .zero, centre: centre, radius: 4, tangent: false))
  let tangent = try #require(
    FiveWayCircleComparison.linearCoverage(at: .zero, centre: centre, radius: 4, tangent: true))
  let exact = analyticalDiskCoverage(at: .zero, centre: centre, radius: 4)
  #expect(chord > 0 && chord < exact && exact < tangent)
  #expect(tangent == 0.5)
  for tangent in [false, true] {
    #expect(
      FiveWayCircleComparison.linearCoverage(
        at: .zero, centre: DrawingPoint(x: 0.5, y: 0.5), radius: 0.25, tangent: tangent) == nil)
    #expect(
      FiveWayCircleComparison.linearCoverage(
        at: .zero, centre: DrawingPoint(x: 0.5, y: 0.5), radius: 0.6, tangent: tangent) == nil)
  }
}
