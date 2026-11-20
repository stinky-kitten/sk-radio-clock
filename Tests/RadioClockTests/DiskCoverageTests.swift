//
//  DiskCoverageTests.swift
//  sk-radio-clock
//
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

@Test("Disk coverage uses unit cells with exact full, empty and tangent results")
func diskCoverageFullEmptyAndTangent() {
  let centre = DrawingPoint(x: 0.5, y: 0.5)
  #expect(diskCoverage(at: .zero, centre: centre, radius: 0.75) == 1)
  #expect(diskCoverage(at: PixelPoint(x: 2, y: 0), centre: centre, radius: 0.75) == 0)
  #expect(diskCoverage(at: PixelPoint(x: 1, y: 0), centre: centre, radius: 0.5) == 0)

  // The closest corner of this cell is exactly five units from the disk centre.
  let cornerCell = PixelPoint(x: 3, y: 4)
  #expect(diskCoverage(at: cornerCell, centre: .zero, radius: 5) == 0)
  #expect(diskCoverage(at: cornerCell, centre: .zero, radius: Float(5).nextUp) > 0)
}

@Test("Disk coverage agrees with known quarter-disk and circular segment areas")
func diskCoverageKnownAreas() {
  #expect(abs(analyticalDiskCoverage(at: .zero, centre: .zero, radius: 1) - Float.pi / 4) < 1e-7)

  // A radius-0.5 disk cut 0.25 from its centre leaves a 120-degree sector
  // minus an isosceles triangle in the neighbouring cell.
  let centre = DrawingPoint(x: 0.25, y: 0.5)
  let cap = Float.pi / 12 - Float(3).squareRoot() / 16
  #expect(abs(analyticalDiskCoverage(at: PixelPoint(x: -1, y: 0), centre: centre, radius: 0.5) - cap) < 1e-7)
  #expect(abs(analyticalDiskCoverage(at: .zero, centre: centre, radius: 0.5) - (Float.pi / 4 - cap)) < 1e-7)
}

@Test(
  "Subpixel disks conserve area inside a cell and across cell boundaries",
  arguments: [0.25, 0.015625, 1e-12] as [Float])
func diskCoverageSubpixel(_ radius: Float) {
  let area = Float.pi * radius * radius
  let inside = analyticalDiskCoverage(at: .zero, centre: DrawingPoint(x: 0.375, y: 0.625), radius: radius)
  let onEdge = analyticalDiskCoverage(at: .zero, centre: DrawingPoint(x: 0, y: 0.5), radius: radius)
  let onCorner = analyticalDiskCoverage(at: .zero, centre: .zero, radius: radius)
  #expect(abs(inside / area - 1) < 1e-6)
  #expect(abs(onEdge / area - 0.5) < 1e-6)
  #expect(abs(onCorner / area - 0.25) < 1e-6)
}

@Test("Disk coverage respects reflection, axis exchange and cell translation")
func diskCoverageSymmetry() {
  let centre = DrawingPoint(x: 0.25, y: -0.375)
  let radius: Float = 2.375
  for y in -4...3 {
    for x in -4...3 {
      let original = diskCoverage(at: PixelPoint(x: x, y: y), centre: centre, radius: radius)
      let reflected = diskCoverage(
        at: PixelPoint(x: -x - 1, y: y), centre: DrawingPoint(x: -centre.x, y: centre.y), radius: radius)
      let transposed = diskCoverage(
        at: PixelPoint(x: y, y: x), centre: DrawingPoint(x: centre.y, y: centre.x), radius: radius)
      let translated = diskCoverage(
        at: PixelPoint(x: x + 8, y: y - 5), centre: DrawingPoint(x: centre.x + 8, y: centre.y - 5), radius: radius)
      #expect(abs(original - reflected) < 1e-7)
      // The two axes accumulate the same chord areas in different Float orders.
      #expect(abs(original - transposed) < 5e-7)
      #expect(original == translated)
    }
  }
}

@Test(
  "Summed coverage remains the disk area as the centre moves fractionally",
  arguments: [DrawingPoint.zero, DrawingPoint(x: 0.25, y: 0.625), DrawingPoint(x: -0.375, y: -0.125)],
  [0.375, 1.25, 4.75, 30.5] as [Float])
func diskCoverageAreaConservation(_ centre: DrawingPoint, _ radius: Float) {
  let extent = Int(radius.rounded(.up)) + 1
  var total = 0.0
  for y in -extent..<extent {
    for x in -extent..<extent {
      let coverage = analyticalDiskCoverage(at: PixelPoint(x: x, y: y), centre: centre, radius: radius)
      #expect((0...1).contains(coverage))
      total += Double(coverage)
    }
  }
  let area = Double.pi * Double(radius) * Double(radius)
  #expect(abs(total - area) < area * 1e-7)
}

@Test("Disk coverage remains bounded at near-tangent and large-radius edges")
func diskCoverageNumericalStability() {
  let centre = DrawingPoint(x: 0.5, y: 0.5)
  let neighbour = PixelPoint(x: 1, y: 0)
  let grazing = diskCoverage(at: neighbour, centre: centre, radius: Float(0.5).nextUp)
  let wider = diskCoverage(at: neighbour, centre: centre, radius: 0.5001)
  #expect(grazing > 0 && grazing < wider && wider < 0.00001)

  let radius: Float = 1_048_576
  let shallowArc = diskCoverage(at: .zero, centre: DrawingPoint(x: -radius + 0.5, y: 0.5), radius: radius)
  let reference = analyticalDiskCoverage(at: .zero, centre: DrawingPoint(x: -radius + 0.5, y: 0.5), radius: radius)
  #expect(reference < 0.5 && reference > 0.499999)
  #expect(abs(shallowArc - reference) < 1e-6)
  #expect(diskCoverage(at: .zero, centre: centre, radius: .greatestFiniteMagnitude) == 1)
}

@Test("Zero, negative and nonfinite disk geometry has zero coverage")
func diskCoverageInvalidGeometry() {
  for radius: Float in [0, -1, .nan, .infinity, -.infinity] {
    #expect(diskCoverage(at: .zero, centre: .zero, radius: radius) == 0)
  }
  for value: Float in [.nan, .infinity, -.infinity] {
    #expect(diskCoverage(at: .zero, centre: DrawingPoint(x: value, y: 0), radius: 1) == 0)
    #expect(diskCoverage(at: .zero, centre: DrawingPoint(x: 0, y: value), radius: 1) == 0)
  }
}

@Test("Chord coverage stays close to analytical area across complete and clipped disks")
func diskCoverageApproximationError() {
  let centres = [
    DrawingPoint.zero, DrawingPoint(x: 0.5, y: 0.5), DrawingPoint(x: 0.125, y: 0.375),
    DrawingPoint(x: 0.75, y: 0.25), DrawingPoint(x: -0.375, y: 0.625),
    DrawingPoint(x: 0.4999, y: 0.5001),
  ]
  var maxError = 0.0
  var sumError = 0.0
  var boundaryCount = 0
  var maxByteError = 0
  var maxAreaError = 0.0
  var maxRelativeAreaError = 0.0
  var radiusFourAreaError = 0.0
  var maxOverestimate = 0.0
  for radius: Float in [0.125, 0.25, 0.375, 0.4999, 0.5, 0.5001, 1, 2, 4, 8, 30.5] {
    let extent = Int(radius.rounded(.up)) + 1
    for centre in centres {
      var total = 0.0
      for y in -extent..<extent {
        for x in -extent..<extent {
          let pixel = PixelPoint(x: x, y: y)
          let actual = diskCoverage(at: pixel, centre: centre, radius: radius)
          let reference = analyticalDiskCoverage(at: pixel, centre: centre, radius: radius)
          total += Double(actual)
          #expect((0...1).contains(actual))
          if reference == 0 || reference == 1 {
            #expect(abs(actual - reference) < 1e-6)
          } else {
            let error = Double(actual) - Double(reference)
            maxError = max(maxError, abs(error))
            maxOverestimate = max(maxOverestimate, error)
            sumError += abs(error)
            boundaryCount += 1
            maxByteError = max(maxByteError, abs(Int(actual.unitQuantized8) - Int(reference.unitQuantized8)))
          }
        }
      }
      let area = Double.pi * Double(radius) * Double(radius)
      maxAreaError = max(maxAreaError, abs(total - area))
      maxRelativeAreaError = max(maxRelativeAreaError, abs(total - area) / area)
      if radius == 4 {
        radiusFourAreaError = max(radiusFourAreaError, abs(total - area) / area)
      }
    }
  }
  print(
    "Chord coverage: max \(maxError), mean \(sumError / Double(boundaryCount)) across \(boundaryCount) boundary cells, max byte \(maxByteError), max area \(maxAreaError), max relative area \(maxRelativeAreaError), max overestimate \(maxOverestimate)"
  )
  // Up to four quadrant segments can contribute to one cell. Each is
  // refined against a 1/255 area bound before quantisation.
  #expect(maxError <= 0.006)
  #expect(maxByteError <= 2)
  // Relative error is most sensitive for tiny disks with sub-byte fragments.
  #expect(maxRelativeAreaError <= 0.11)
  print("Radius-4 maximum relative area error: \(radiusFourAreaError)")
  #expect(maxOverestimate <= 1e-6)
}
