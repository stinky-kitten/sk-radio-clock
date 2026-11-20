//
//  LineCoverageTests.swift
//  sk-radio-clock
//
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Foundation
import Testing

@testable import RadioClockLogic

@Test(
  "Line coverage matches known areas under reflection, axis exchange and side reversal",
  arguments: [
    (DrawingPoint(x: 0.5, y: 0), DrawingPoint(x: 1, y: 1), Float(0.875)),
    (DrawingPoint(x: 0.75, y: 0), DrawingPoint(x: 2, y: 1), 0.5),
    (DrawingPoint(x: 0.25, y: 0), DrawingPoint(x: 1, y: 0), 0.75),
    (DrawingPoint(x: 0, y: 0), DrawingPoint(x: 1, y: -1), 0.5),
    (DrawingPoint(x: 0, y: 0), DrawingPoint(x: 1, y: 0), 1),
    (DrawingPoint(x: 1, y: 0), DrawingPoint(x: 1, y: 0), 0),
    (DrawingPoint(x: 1, y: 1), DrawingPoint(x: 1, y: 1), 0),
    (DrawingPoint(x: -0.25, y: 0), DrawingPoint(x: 1, y: 1), 1),
    (DrawingPoint(x: 2, y: 0), DrawingPoint(x: 1, y: 1), 0),
  ])
func lineCoverageKnownAreas(_ point: DrawingPoint, _ normal: DrawingPoint, _ expected: Float) {
  let pixel = PixelPoint(x: -3, y: 4)
  for swap in [false, true] {
    for sx: Float in [-1, 1] {
      for sy: Float in [-1, 1] {
        let x = swap ? point.y : point.x
        let y = swap ? point.x : point.y
        let translated = DrawingPoint(
          x: Float(pixel.x) + (sx < 0 ? 1 - x : x), y: Float(pixel.y) + (sy < 0 ? 1 - y : y))
        let direction = DrawingPoint(x: sx * (swap ? normal.y : normal.x), y: sy * (swap ? normal.x : normal.y))
        let reversed = DrawingPoint(x: -direction.x, y: -direction.y)
        #expect(lineCoverage(at: pixel, through: translated, normal: direction) == expected)
        #expect(lineCoverage(at: pixel, through: translated, normal: reversed) == 1 - expected)
      }
    }
  }
}

@Test("Line coverage agrees with independently clipped polygons across fractional positions and orientations")
func lineCoverageReference() {
  let pixel = PixelPoint(x: -2, y: 3)
  var maximum = 0.0
  var sum = 0.0
  var count = 0
  var maximumByte = 0
  for index in 0..<128 {
    let angle = Double(index) * .pi / 64
    let normal = DrawingPoint(x: Float(cos(angle)), y: Float(sin(angle)))
    let reversed = DrawingPoint(x: -normal.x, y: -normal.y)
    for offset in -32...32 {
      let distance = Float(offset) / 37
      let point = DrawingPoint(x: -1.53 + distance * normal.x, y: 3.43 + distance * normal.y)
      let expected = clippedPixelArea(pixel, point: point, normal: normal)
      let actual = lineCoverage(at: pixel, through: point, normal: normal)
      let complement = lineCoverage(at: pixel, through: point, normal: reversed)
      #expect((0...1).contains(actual))
      #expect(abs(actual + complement - 1) <= 3e-7)
      let error = abs(Double(actual) - expected)
      maximum = max(maximum, error)
      sum += error
      count += 1
      maximumByte = max(maximumByte, abs(Int((actual * 255).rounded()) - Int((expected * 255).rounded())))
    }
  }
  print("Line coverage over \(count) cases: max \(maximum), mean \(sum / Double(count)), max byte \(maximumByte)")
  #expect(maximum <= 3e-7)
  #expect(maximumByte <= 1)
}

@Test("Nearly tangent lines retain small triangular coverage and invalid lines cover nothing")
func lineCoverageGrazingAndInvalid() {
  let normal = DrawingPoint(x: 1, y: 1)
  let point = DrawingPoint(x: Float(1).nextDown, y: 1)
  let expected = clippedPixelArea(.zero, point: point, normal: normal)
  let actual = lineCoverage(at: .zero, through: point, normal: normal)
  #expect(actual > 0 && expected > 0)
  #expect(abs(Double(actual) - expected) < 1e-14)
  #expect(lineCoverage(at: .zero, through: .zero, normal: .zero) == 0)
  #expect(lineCoverage(at: .zero, through: .zero, normal: DrawingPoint(x: .infinity, y: 1)) == 0)
  #expect(lineCoverage(at: .zero, through: DrawingPoint(x: .nan, y: 0), normal: normal) == 0)
}

@Test("Finite normals preserve both halves when either corner dot product would overflow")
func lineCoverageNormalOverflow() {
  let magnitude = Float.greatestFiniteMagnitude
  let normal = DrawingPoint(x: magnitude, y: magnitude)
  let reverse = DrawingPoint(x: -magnitude, y: -magnitude)
  let fixtures: [(DrawingPoint, Float)] = [
    (DrawingPoint(x: -1, y: -1), 1),
    (DrawingPoint(x: 2, y: 2), 0),
    (DrawingPoint(x: 0.75, y: 0.75), 0.125),
    (DrawingPoint(x: 0.125, y: 0.125), 0.96875),
  ]
  for (point, expected) in fixtures {
    #expect(clippedPixelArea(.zero, point: point, normal: normal) == Double(expected))
    #expect(lineCoverage(at: .zero, through: point, normal: normal) == expected)
    #expect(lineCoverage(at: .zero, through: point, normal: reverse) == 1 - expected)
  }
}

@Test(
  "Extreme positive normal scales preserve axis-aligned, corner and transition coverage",
  arguments: [
    Float.leastNonzeroMagnitude, .leastNormalMagnitude, 0x1p-80, 0x1p-63, 1, 0x1p62, 0x1p63, 0x1p126,
  ] as [Float])
func lineCoverageNormalScaling(_ scale: Float) {
  let fixtures: [(DrawingPoint, DrawingPoint, Float)] = [
    (DrawingPoint(x: 0.25, y: 0), DrawingPoint(x: 1, y: -0.0), 0.75),
    (DrawingPoint(x: 0, y: 0.75), DrawingPoint(x: -0.0, y: -1), 0.75),
    (DrawingPoint(x: 0, y: 0), DrawingPoint(x: 1, y: -1), 0.5),
    (DrawingPoint(x: 0.5, y: 0), DrawingPoint(x: 2, y: 1), 0.75),
    (DrawingPoint(x: 1, y: 0), DrawingPoint(x: 2, y: 1), 0.25),
  ]
  for (point, unitNormal, expected) in fixtures {
    let normal = DrawingPoint(x: unitNormal.x * scale, y: unitNormal.y * scale)
    let reverse = DrawingPoint(x: -normal.x, y: -normal.y)
    #expect(lineCoverage(at: .zero, through: point, normal: normal) == expected)
    #expect(lineCoverage(at: .zero, through: point, normal: reverse) == 1 - expected)
    #expect(clippedPixelArea(.zero, point: point, normal: normal) == Double(expected))
  }

  for x in [Float(0.5).nextDown, 0.5, Float(0.5).nextUp, Float(1).nextDown, 1, Float(1).nextUp] {
    let point = DrawingPoint(x: x, y: 0)
    let original = DrawingPoint(x: 2, y: 1)
    let normal = DrawingPoint(x: 2 * scale, y: scale)
    let reflectedPoint = DrawingPoint(x: point.y, y: point.x)
    let reflectedNormal = DrawingPoint(x: normal.y, y: normal.x)
    let reverse = DrawingPoint(x: -normal.x, y: -normal.y)
    let actual = lineCoverage(at: .zero, through: point, normal: normal)
    let complement = lineCoverage(at: .zero, through: point, normal: reverse)
    #expect(actual == lineCoverage(at: .zero, through: point, normal: original))
    #expect(actual == lineCoverage(at: .zero, through: reflectedPoint, normal: reflectedNormal))
    #expect(abs(Double(actual) - clippedPixelArea(.zero, point: point, normal: normal)) <= 1e-7)
    #expect(abs(actual + complement - 1) <= 1e-7)
  }

  // A subnormal normal can still represent the same small triangular cap.
  let point = DrawingPoint(x: Float(1).nextDown, y: 1)
  let normal = DrawingPoint(x: scale, y: scale)
  let actual = lineCoverage(at: .zero, through: point, normal: normal)
  #expect(actual > 0)
  #expect(abs(Double(actual) - clippedPixelArea(.zero, point: point, normal: normal)) < 1e-14)
  #expect(lineCoverage(at: .zero, through: .zero, normal: DrawingPoint(x: -0.0, y: 0.0)) == 0)
}

@Test("Distant line anchors retain a small normal component's contribution")
func lineCoverageDistantAnchor() {
  let limit = Float.greatestFiniteMagnitude
  let fixtures: [(DrawingPoint, DrawingPoint, Float)] = [
    (DrawingPoint(x: 0, y: limit), DrawingPoint(x: limit, y: 0x1p-24), 1 - 0x1p-24),
    (DrawingPoint(x: -limit, y: -limit), DrawingPoint(x: 1, y: 1), 1),
    (DrawingPoint(x: limit, y: limit), DrawingPoint(x: 1, y: 1), 0),
  ]
  for (point, normal, expected) in fixtures {
    let reverse = DrawingPoint(x: -normal.x, y: -normal.y)
    #expect(lineCoverage(at: .zero, through: point, normal: normal) == expected)
    #expect(lineCoverage(at: .zero, through: point, normal: reverse) == 1 - expected)
    #expect(clippedPixelArea(.zero, point: point, normal: normal) == Double(expected))
  }
}

@Test("Scaled oblique lines agree with the clipped polygon within Float precision")
func lineCoverageScaledReference() {
  let pixel = PixelPoint(x: -2, y: 3)
  for normal in [DrawingPoint(x: 0.6, y: -0.8), DrawingPoint(x: -0.3, y: 0.7)] {
    for point in [
      DrawingPoint(x: -1.75, y: 3.25), DrawingPoint(x: -1.37, y: 3.7), DrawingPoint(x: -1.001, y: 3.98),
    ] {
      let original = lineCoverage(at: pixel, through: point, normal: normal)
      for scale: Float in [1e-37, 1e-25, 0.1, 3, 1e25, 1e37] {
        let scaled = DrawingPoint(x: normal.x * scale, y: normal.y * scale)
        let reverse = DrawingPoint(x: -scaled.x, y: -scaled.y)
        let actual = lineCoverage(at: pixel, through: point, normal: scaled)
        let expected = clippedPixelArea(pixel, point: point, normal: scaled)
        #expect(abs(actual - original) <= 3e-7)
        #expect(abs(Double(actual) - expected) <= 3e-7)
        #expect(abs(actual + lineCoverage(at: pixel, through: point, normal: reverse) - 1) <= 3e-7)
      }
    }
  }
}

// Clip the four square vertices and measure the resulting polygon by shoelace.
private func clippedPixelArea(_ pixel: PixelPoint, point: DrawingPoint, normal: DrawingPoint) -> Double {
  let square: [(x: Double, y: Double)] = [(0, 0), (1, 0), (1, 1), (0, 1)]
  let px = Double(point.x) - Double(pixel.x)
  let py = Double(point.y) - Double(pixel.y)
  func side(_ vertex: (x: Double, y: Double)) -> Double {
    (vertex.x - px) * Double(normal.x) + (vertex.y - py) * Double(normal.y)
  }
  var polygon: [(x: Double, y: Double)] = []
  for index in square.indices {
    let a = square[index]
    let b = square[(index + 1) % square.count]
    let fa = side(a)
    let fb = side(b)
    if fa >= 0 { polygon.append(a) }
    if (fa >= 0) != (fb >= 0) {
      let t = fa / (fa - fb)
      polygon.append((a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)))
    }
  }
  // Translate before summing so tiny triangles at (1, 1) retain their area.
  guard let origin = polygon.first else { return 0 }
  var twiceArea = 0.0
  for index in polygon.indices {
    let a = polygon[index]
    let b = polygon[(index + 1) % polygon.count]
    twiceArea += (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
  }
  return abs(twiceArea) / 2
}
