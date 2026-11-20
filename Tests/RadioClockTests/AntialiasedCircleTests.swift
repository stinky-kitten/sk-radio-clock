//
//  AntialiasedCircleTests.swift
//  sk-radio-clock
//
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

private struct CircleCoverageRecorder: CoverageSpanRasterTarget {
  let contextSize: PixelSize
  var rows: [[UInt8]]
  var paintedRows: Set<Int> = []
  var constantRows: Set<Int> = []

  init(width: Int = 8, height: Int = 8) {
    contextSize = PixelSize(width: width, height: height)
    rows = Array(repeating: Array(repeating: 0, count: width), count: height)
  }

  mutating func paintSpan(y: Int, from x: Int, to endX: Int, coverage: UInt8, operation: DrawingOperation) -> Bool {
    constantRows.insert(y)
    return record(y: y, x: x, count: endX - x, operation: operation) { _ in coverage }
  }

  mutating func paintSpan(y: Int, from x: Int, coverage: Span<UInt8>, operation: DrawingOperation) -> Bool {
    let count = coverage.count
    return record(y: y, x: x, count: count, operation: operation) { coverage[$0] }
  }

  private mutating func record(
    y: Int, x: Int, count: Int, operation: DrawingOperation, sample: (Int) -> UInt8
  ) -> Bool {
    #expect(operation == .fill)
    guard y >= 0, y < contextSize.height, x >= 0, count > 0, x + count <= contextSize.width else {
      Issue.record("Circle emitted an invalid span")
      return false
    }
    #expect(paintedRows.insert(y).inserted)
    for offset in 0..<count { rows[y][x + offset] = sample(offset) }
    return true
  }
}

@Test(
  "Antialiased circle coverage approximates independent integration across each unit cell",
  arguments: [
    (DrawingPoint(x: 4, y: 4), Float(2)),
    (DrawingPoint(x: 4.25, y: 3.625), 2.875),
    (DrawingPoint(x: 4, y: 4), 0.25),
    (DrawingPoint(x: 0.125, y: 3.75), 2.25),
    (DrawingPoint(x: 7.875, y: 3.75), 2.25),
    (DrawingPoint(x: 3.75, y: 0.125), 2.25),
    (DrawingPoint(x: 3.75, y: 7.875), 2.25),
    (DrawingPoint(x: -20, y: 4), 24),
  ])
func antialiasedCircleReference(_ centre: DrawingPoint, _ radius: Float) {
  var recorder = CircleCoverageRecorder()
  var row: InlineArray<8, UInt8> = .init(repeating: 0)
  var scratch = row.mutableSpan
  let completed = recorder.fillAntialiasedCircle(centre: centre, radius: radius, coverageRow: &scratch)
  #expect(completed)
  for y in 0..<8 {
    for x in 0..<8 {
      let area = integratedCircleCell(x: x, y: y, centre: centre, radius: radius)
      let expected = Int((area * 255).rounded())
      #expect(abs(Int(recorder.rows[y][x]) - expected) <= 5, "Pixel (\(x), \(y))")
    }
  }
}

// Numerically integrate vertical chord lengths independently of the analytic disk helper.
private func integratedCircleCell(x: Int, y: Int, centre: DrawingPoint, radius: Float) -> Double {
  let steps = 4096
  let radiusSquared = Double(radius) * Double(radius)
  var area = 0.0
  for step in 0..<steps {
    let dx = Double(x) + (Double(step) + 0.5) / Double(steps) - Double(centre.x)
    let chord = max(0, radiusSquared - dx * dx).squareRoot()
    let top = max(Double(y), Double(centre.y) - chord)
    let bottom = min(Double(y + 1), Double(centre.y) + chord)
    area += max(0, bottom - top)
  }
  return area / Double(steps)
}

@Test("Antialiased circles distinguish a cell centre, a grid corner and grazing contact")
func antialiasedCircleCellCoordinates() {
  var row: InlineArray<8, UInt8> = .init(repeating: 0)
  var scratch = row.mutableSpan

  var recorder = CircleCoverageRecorder()
  let centre = PixelPoint(x: 3, y: 3).drawingCentre
  let centred = recorder.fillAntialiasedCircle(centre: centre, radius: 0.5, coverageRow: &scratch)
  #expect(centred)
  #expect(recorder.paintedRows == [3])
  #expect(recorder.rows[3] == [0, 0, 0, 200, 0, 0, 0, 0])

  recorder = CircleCoverageRecorder()
  let corner = recorder.fillAntialiasedCircle(
    centre: DrawingPoint(x: 4, y: 4), radius: 0.25, coverageRow: &scratch)
  #expect(corner)
  #expect(recorder.paintedRows == [3, 4])
  #expect(recorder.rows[3][0..<3].allSatisfy { $0 == 0 })
  #expect((9...13).contains(recorder.rows[3][3]))
  #expect(recorder.rows[3][3] == recorder.rows[3][4])
  #expect(recorder.rows[3][5...].allSatisfy { $0 == 0 })
  #expect(recorder.rows[3] == recorder.rows[4])

  recorder = CircleCoverageRecorder()
  let tangent = recorder.fillAntialiasedCircle(
    centre: DrawingPoint(x: -0.5, y: 3.5), radius: 0.5, coverageRow: &scratch)
  #expect(tangent && recorder.paintedRows.isEmpty)
  let grazing = recorder.fillAntialiasedCircle(
    centre: DrawingPoint(x: -0.5, y: 3.5), radius: 0.52, coverageRow: &scratch)
  #expect(grazing)
  #expect(recorder.paintedRows == [3])
  #expect(recorder.rows[3] == [1, 0, 0, 0, 0, 0, 0, 0])
}

@Test("A disk covering the entire surface emits one full constant span per row")
func antialiasedCircleFullRows() {
  var recorder = CircleCoverageRecorder(width: 8, height: 4)
  var row: InlineArray<8, UInt8> = .init(repeating: 0)
  var scratch = row.mutableSpan
  let completed = recorder.fillAntialiasedCircle(
    centre: DrawingPoint(x: 4, y: 2), radius: 30, coverageRow: &scratch)
  #expect(completed)
  #expect(recorder.constantRows == [0, 1, 2, 3])
  #expect(recorder.rows == Array(repeating: Array(repeating: 255, count: 8), count: 4))
}

@Test(
  "Antialiased circle deadline expiry finishes the mixed row and leaves later rows unwritten",
  arguments: [(DrawingPoint(x: 4, y: 0.5), Float(2.25)), (DrawingPoint(x: -3.25, y: -22.5), 24)])
func antialiasedCircleDeadline(_ centre: DrawingPoint, _ radius: Float) throws {
  let size = PixelSize(width: 8, height: 4)
  let background: UInt32 = 0xff00_00ff
  var pixels = Array(repeating: background, count: 32)
  try pixels.withUnsafeMutableBufferPointer { framebuffer in
    var context = try #require(
      DrawingContext(
        framebuffer: framebuffer, contextSize: size, pixelFormat: .bgrx8888,
        renderDeadline: RenderDeadline(timeUs: 100)))
    context.fillColor = PixelColor32(rawValue: 0x80ff_0000)
    var row: InlineArray<8, UInt8> = .init(repeating: 0)
    var scratch = row.mutableSpan
    RenderHostTime.withTimestamps([99, 100]) {
      let completed = context.fillAntialiasedCircle(centre: centre, radius: radius, coverageRow: &scratch)
      #expect(!completed)
      #expect(context.status == .deadlineExceeded && RenderHostTime.readCount == 2)
      let retry = context.fillAntialiasedCircle(centre: centre, radius: radius, coverageRow: &scratch)
      #expect(!retry && RenderHostTime.readCount == 2)
    }
  }
  let firstRow = (0..<8).map { x -> UInt32 in
    let coverage = UInt32(
      (255 * integratedCircleCell(x: x, y: 0, centre: centre, radius: radius)).rounded())
    let alpha = (128 * coverage + 127) / 255
    return 0xff00_0000 | (alpha << 16) | (255 - alpha)
  }
  for x in 0..<8 {
    let expected = firstRow[x]
    let actual = pixels[x]
    if expected == background || expected == 0xff80_007f {
      #expect(actual == expected)
    } else {
      #expect(abs(Int((actual >> 16) & 255) - Int((expected >> 16) & 255)) <= 3)
      #expect(abs(Int(actual & 255) - Int(expected & 255)) <= 3)
    }
  }
  #expect(pixels.dropFirst(8).allSatisfy { $0 == background })
}

@Test("Tangent classification preserves full, empty, grazing and ambiguous circle cells")
func tangentCircleCellClassification() throws {
  let centre = DrawingPoint(x: 32.25, y: 32)
  let cardinal = PixelPoint(x: 32, y: 28)
  #expect(tangentCircleCoverage(at: cardinal, centre: centre, radius: 4) == nil)
  #expect(tangentCircleCoverage(at: PixelPoint(x: 32, y: 32), centre: centre, radius: 4) == 1)
  #expect(tangentCircleCoverage(at: PixelPoint(x: 32, y: 27), centre: centre, radius: 4) == 0)

  let corner = PixelPoint(x: 3, y: 4)
  #expect(tangentCircleCoverage(at: corner, centre: .zero, radius: 5) == 0)
  let grazing = tangentCircleCoverage(at: corner, centre: .zero, radius: Float(5).nextUp)
  #expect(grazing == nil || (grazing ?? 0) > 0)
  #expect(diskCoverage(at: corner, centre: .zero, radius: Float(5).nextUp) > 0)

  let contained = DrawingPoint(x: 0.5, y: 0.5)
  #expect(tangentCircleCoverage(at: .zero, centre: contained, radius: 0.25) == nil)
  #expect(diskCoverage(at: .zero, centre: contained, radius: 0.25) == Float.pi / 16)
  // The disk crosses all four edges, with two intersections on each edge.
  #expect(tangentCircleCoverage(at: .zero, centre: contained, radius: Float(0.5).nextUp) == nil)
}

@Test("Production circle selects tangent at radius 24 and uses the Float fallback")
func antialiasedCircleTangentSelection() {
  let cutoff: Float = 24
  let radii: [Float] = [0.25, 0.5, 4, 12, cutoff.nextDown, cutoff, cutoff.nextUp, 32, 47]
  var row: InlineArray<64, UInt8> = .init(repeating: 0)
  var scratch = row.mutableSpan
  var sawFloatFallbackDifference = false
  var sawTangentDifference = false
  var maxAreaError: Float = 0
  var maxByteError = 0
  var maxHistoricalByteDifference = 0
  var maxCutoffDifference = 0
  var maxSameAlgorithmDifference = 0

  for position in 0..<16 {
    let centre = DrawingPoint(x: 32 + Float(position % 4) / 4, y: 32 + Float(position / 4) / 4)
    var belowCutoff: [[UInt8]] = []
    var refinedBelow: [[UInt8]] = []
    for radius in radii {
      var recorder = CircleCoverageRecorder(width: 64, height: 64)
      #expect(recorder.fillAntialiasedCircle(centre: centre, radius: radius, coverageRow: &scratch))
      var refined = CircleCoverageRecorder(width: 64, height: 64)
      #expect(refined.fillRefinedChordCircle(centre: centre, radius: radius, coverageRow: &scratch))
      if radius < cutoff {
        #expect(recorder.rows == refined.rows)
      }
      if radius == cutoff.nextDown {
        belowCutoff = recorder.rows
        refinedBelow = refined.rows
      }
      for y in 0..<64 {
        for x in 0..<64 {
          let pixel = PixelPoint(x: x, y: y)
          let exact = analyticalDiskCoverage(at: pixel, centre: centre, radius: radius)
          let actual = recorder.rows[y][x]
          let chord = diskCoverage(at: pixel, centre: centre, radius: radius)
          #expect(refined.rows[y][x] == chord.unitQuantized8)
          let tangent =
            radius >= cutoff
            ? FiveWayCircleComparison.linearCoverage(at: pixel, centre: centre, radius: radius, tangent: true)
            : nil
          let expected = tangent ?? chord
          #expect(actual == expected.unitQuantized8)
          if exact == 0 || exact == 1 {
            #expect(actual == exact.unitQuantized8)
          }
          maxAreaError = max(maxAreaError, abs(expected - exact))
          maxByteError = max(maxByteError, abs(Int(actual) - Int(exact.unitQuantized8)))
          if radius >= cutoff {
            let historical = (tangent ?? exact).unitQuantized8
            let delta = abs(Int(actual) - Int(historical))
            maxHistoricalByteDifference = max(maxHistoricalByteDifference, delta)
            if tangent == nil, delta > 0 { sawFloatFallbackDifference = true }
            if tangent != nil, actual != refined.rows[y][x] { sawTangentDifference = true }
          }
          if radius == cutoff {
            maxCutoffDifference = max(maxCutoffDifference, abs(Int(actual) - Int(belowCutoff[y][x])))
            maxSameAlgorithmDifference = max(
              maxSameAlgorithmDifference, abs(Int(refined.rows[y][x]) - Int(refinedBelow[y][x])))
          }
        }
      }
    }
  }
  #expect(sawFloatFallbackDifference && sawTangentDifference)
  #expect(maxHistoricalByteDifference <= 1)
  #expect(maxAreaError <= 0.006)
  #expect(maxByteError <= 2)
  #expect(maxCutoffDifference <= 2)
  print(
    "Production tangent sweep: max area=\(maxAreaError) max byte=\(maxByteError) historical max byte=\(maxHistoricalByteDifference) cutoff max byte=\(maxCutoffDifference) refined-only cutoff max byte=\(maxSameAlgorithmDifference)"
  )
}
