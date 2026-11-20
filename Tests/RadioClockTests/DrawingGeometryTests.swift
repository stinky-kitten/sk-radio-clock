//
//  DrawingGeometryTests.swift
//  sk-radio-clock
//
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

private struct RecordingSpanTarget: SpanRasterTarget {
  let contextSize: PixelSize
  var spans: [PixelRect] = []

  mutating func paintSpan(y: Int, from left: Int, to right: Int) -> Bool {
    spans.append(PixelRect(x: left, y: y, width: right - left, height: 1))
    return true
  }
}

@Test(
  "Quad spans clip to the exact integer right and bottom edges of large surfaces",
  arguments: [16_777_217, 16_777_219])
func drawingLargeQuadSpanClipping(_ dimension: Int) {
  let start = dimension - 1
  let quad = DrawingQuad(vertices: [
    DrawingPoint(x: Float(start), y: Float(start)),
    DrawingPoint(x: 16_777_224, y: Float(start)),
    DrawingPoint(x: 16_777_224, y: 16_777_224),
    DrawingPoint(x: Float(start), y: 16_777_224),
  ])
  var target = RecordingSpanTarget(contextSize: PixelSize(width: dimension, height: dimension))

  let completed = target.fillQuad(quad)
  #expect(completed)
  #expect(target.spans == [PixelRect(x: start, y: start, width: 1, height: 1)])
}

@Test("Circle spans clip to the exact integer right and bottom edges of large surfaces")
func drawingLargeCircleSpanClipping() {
  let dimension = 16_777_219
  let centre = DrawingPoint(x: 16_777_218, y: 16_777_220)
  var target = RecordingSpanTarget(contextSize: PixelSize(width: dimension, height: dimension))

  let completed = target.fillCircle(centre: centre, radius: 2)
  #expect(completed)
  #expect(target.spans == [PixelRect(x: dimension - 1, y: dimension - 1, width: 1, height: 1)])
}

@Test(
  "Pixel centres are half a unit from the pixel origin",
  arguments: [
    (PixelPoint(x: 0, y: 0), DrawingPoint(x: 0.5, y: 0.5)),
    (PixelPoint(x: 9, y: 9), DrawingPoint(x: 9.5, y: 9.5)),
    (PixelPoint(x: -1, y: -1), DrawingPoint(x: -0.5, y: -0.5)),
  ])
func drawingPixelCentre(_ pixel: PixelPoint, _ expected: DrawingPoint) {
  #expect(pixel.drawingCentre == expected)
}

@Test(
  "Containing pixel floors both coordinates, including negative coordinates",
  arguments: [
    (DrawingPoint(x: 0, y: 0), PixelPoint(x: 0, y: 0)),
    (DrawingPoint(x: 0.5, y: 0.5), PixelPoint(x: 0, y: 0)),
    (DrawingPoint(x: 0.999, y: 0.999), PixelPoint(x: 0, y: 0)),
    (DrawingPoint(x: 1, y: 1), PixelPoint(x: 1, y: 1)),
    (DrawingPoint(x: -0.25, y: 1.5), PixelPoint(x: -1, y: 1)),
    (DrawingPoint(x: -1, y: -1), PixelPoint(x: -1, y: -1)),
  ])
func drawingContainingPixel(_ point: DrawingPoint, _ expected: PixelPoint) {
  #expect(point.pixelContainingPoint == expected)
}

@Test(
  "Containing pixel rejects nonfinite and out-of-range values on either axis",
  arguments: [Float.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude],
  [false, true])
func drawingInvalidPixelCoordinate(_ coordinate: Float, _ isX: Bool) {
  let point = isX ? DrawingPoint(x: coordinate, y: 0) : DrawingPoint(x: 0, y: coordinate)
  #expect(point.pixelContainingPoint == nil)
}

@Test(
  "Pixel rectangles preserve their origin and dimensions in drawing coordinates",
  arguments: [
    (PixelRect(x: 0, y: 0, width: 10, height: 10), DrawingRect(x: 0, y: 0, width: 10, height: 10)),
    (PixelRect(x: 2, y: 3, width: 4, height: 5), DrawingRect(x: 2, y: 3, width: 4, height: 5)),
    (PixelRect(x: -3, y: -2, width: 4, height: 5), DrawingRect(x: -3, y: -2, width: 4, height: 5)),
    (PixelRect(x: 2, y: -3, width: 0, height: 5), DrawingRect(x: 2, y: -3, width: 0, height: 5)),
    (PixelRect(x: -2, y: 3, width: 4, height: 0), DrawingRect(x: -2, y: 3, width: 4, height: 0)),
  ])
func drawingRectangleConversion(_ rect: PixelRect, _ expected: DrawingRect) {
  #expect(rect.drawingRect == expected)
}

@Test(
  "Drawing rectangle bounds retain fractional and negative dimensions without normalisation",
  arguments: [
    (DrawingRect(x: -1.25, y: 0.375, width: 2.5, height: 0.25), -1.25, 0.375, 1.25, 0.625, 2.5, 0.25),
    (DrawingRect(x: 2.25, y: -0.5, width: -1.5, height: -0.25), 2.25, -0.5, 0.75, -0.75, -1.5, -0.25),
  ] as [(DrawingRect, Float, Float, Float, Float, Float, Float)])
func drawingRectangleBounds(
  _ rect: DrawingRect, _ minX: Float, _ minY: Float, _ maxX: Float, _ maxY: Float, _ width: Float, _ height: Float
) {
  #expect(rect.minX == minX)
  #expect(rect.minY == minY)
  #expect(rect.maxX == maxX)
  #expect(rect.maxY == maxY)
  #expect(rect.width == width)
  #expect(rect.height == height)
}

@Test(
  "Drawing rectangles are nonempty only when both dimensions are positive",
  arguments: [
    (0.25, 0.5, false),
    (0, 1, true),
    (1, 0, true),
    (-1, 1, true),
    (1, -1, true),
    (.nan, 1, true),
    (1, .nan, true),
  ] as [(Float, Float, Bool)])
func drawingRectangleEmptiness(_ width: Float, _ height: Float, _ expected: Bool) {
  let rect = DrawingRect(x: 2, y: -3, width: width, height: height)
  #expect(rect.isEmpty == expected)
}

@Test("The zero drawing rectangle is empty at the origin")
func drawingRectangleZero() {
  #expect(DrawingRect.zero == DrawingRect(x: 0, y: 0, width: 0, height: 0))
  #expect(DrawingRect.zero.isEmpty)
}

private typealias AxisCoverageEdge = (index: Int, coverage: Float)

private let axisCoverageFixtures: [(Range<Float>, AxisCoverageEdge?, Range<Int>?, AxisCoverageEdge?)] = [
  (2..<6, nil, 2..<6, nil),
  (2.25..<5.5, (2, 0.75), 3..<5, (5, 0.5)),
  (2.25..<2.75, (2, 0.5), nil, nil),
  (2..<2.75, nil, nil, (2, 0.75)),
  (2.25..<3, (2, 0.75), nil, nil),
  (2.25..<3.25, (2, 0.75), nil, (3, 0.25)),
  (0..<1, nil, 0..<1, nil),
  // Touch the left and right boundaries of a 64-pixel axis.
  (0..<0.5, nil, nil, (0, 0.5)),
  (63.5..<64, (63, 0.5), nil, nil),
  // Negative coordinates and intervals that cross zero.
  (-3 ..< -1, nil, -3 ..< -1, nil),
  (-2.75 ..< -2.25, (-3, 0.5), nil, nil),
  (-1.75..<1.25, (-2, 0.75), -1..<1, (1, 0.25)),
  (-0.5..<0, (-1, 0.5), nil, nil),
]

@Test("Axis coverage classifies leading, interior and trailing pixels", arguments: axisCoverageFixtures)
private func axisCoverageClassification(
  _ interval: Range<Float>, _ leading: AxisCoverageEdge?, _ interior: Range<Int>?, _ trailing: AxisCoverageEdge?
) {
  let result = AxisCoverage(from: interval.lowerBound, to: interval.upperBound)
  #expect(result.leading?.index == leading?.index && result.leading?.coverage == leading?.coverage)
  if let interior {
    #expect(result.interior == interior)
  } else {
    #expect(result.interior.isEmpty)
  }
  #expect(result.trailing?.index == trailing?.index && result.trailing?.coverage == trailing?.coverage)
}

@Test(
  "Axis coverage represents each intersected pixel once and conserves interval length",
  arguments: axisCoverageFixtures.map { $0.0 } + [0.1..<3.2, -1.1..<0.2])
func axisCoverageInvariants(_ interval: Range<Float>) {
  let start = interval.lowerBound
  let end = interval.upperBound
  let result = AxisCoverage(from: start, to: end)
  let edges = [result.leading, result.trailing].compactMap { $0 }
  let indices = Array(result.interior) + edges.map(\.index)
  let intersectedPixels = Array(Int(start.rounded(.down))..<Int(end.rounded(.up)))
  #expect(indices.sorted() == intersectedPixels)

  let fullPixels = Int(start.rounded(.up))..<max(Int(start.rounded(.up)), Int(end.rounded(.down)))
  #expect(Array(result.interior) == Array(fullPixels))
  #expect(edges.allSatisfy { $0.coverage > 0 && $0.coverage <= 1 })
  if intersectedPixels.count == 1 {
    #expect(edges.count <= 1)
  }

  let length = end - start
  let coveredLength = edges.reduce(Float(result.interior.count)) { $0 + $1.coverage }
  #expect(abs(coveredLength - length) <= 2 * length.ulp)
}
