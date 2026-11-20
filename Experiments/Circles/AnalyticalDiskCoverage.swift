//
//  AnalyticalDiskCoverage.swift
//  sk-radio-clock
//
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

#if SWIFT_PACKAGE
  import Foundation

  @testable import RadioClockLogic
#endif

/// Returns the area of the disk inside the unit cell with `pixel` as its minimum corner.
/// The centre is in destination drawing coordinates. Invalid disks have zero coverage.
func analyticalDiskCoverage(at pixel: PixelPoint, centre: DrawingPoint, radius: Float) -> Float {
  guard centre.x.isFinite, centre.y.isFinite, radius.isFinite, radius > 0 else { return 0 }

  // Use wider intermediates for squared distances and small differences in arc area.
  let radius = Double(radius)
  let left = Double(pixel.x) - Double(centre.x)
  let top = Double(pixel.y) - Double(centre.y)
  let right = left + 1
  let bottom = top + 1

  func halfChordSquared(at offset: Double) -> Double {
    (radius - offset) * (radius + offset)
  }

  let nearX = max(left, -right, 0)
  let nearY = max(top, -bottom, 0)
  let nearMinor = min(nearX, nearY)
  guard nearMinor * nearMinor < halfChordSquared(at: max(nearX, nearY)) else { return 0 }

  let farX = max(abs(left), abs(right))
  let farY = max(abs(top), abs(bottom))
  let farMinor = min(farX, farY)
  if farMinor * farMinor <= halfChordSquared(at: max(farX, farY)) { return 1 }

  let radiusSquared = radius * radius
  if left <= -radius, right >= radius, top <= -radius, bottom >= radius {
    return Float(Double.pi * radiusSquared)
  }

  // Reflect the pieces of the cell into the positive quadrant, where the
  // right edge of the disk decreases monotonically with increasing y.
  func quadrantArea(left: Double, right: Double, top: Double, bottom: Double) -> Double {
    let left = max(0, left)
    let top = max(0, top)
    guard left < right, top < bottom, left < radius, top < radius else { return 0 }

    let fullEnd = min(bottom, max(0, halfChordSquared(at: right)).squareRoot())
    let fullArea = (right - left) * max(0, fullEnd - top)
    let arcStart = max(top, fullEnd)
    let arcEnd = min(bottom, halfChordSquared(at: left).squareRoot())
    guard arcStart < arcEnd else { return fullArea }

    let startX = max(0, halfChordSquared(at: arcStart)).squareRoot()
    let endX = max(0, halfChordSquared(at: arcEnd)).squareRoot()
    let dy = arcEnd - arcStart

    // The curved strip is a trapezoid plus the circular segment above its chord.
    let trapezoid = dy * (max(0, startX - left) + max(0, endX - left)) / 2
    let cross = startX * dy + arcStart * (startX - endX)
    let dot = startX * endX + arcStart * arcEnd
    let segment = max(0, radiusSquared * atan2(cross, dot) - cross) / 2
    return fullArea + trapezoid + segment
  }

  let area =
    quadrantArea(left: left, right: right, top: top, bottom: bottom)
    + quadrantArea(left: -right, right: -left, top: top, bottom: bottom)
    + quadrantArea(left: left, right: right, top: -bottom, bottom: -top)
    + quadrantArea(left: -right, right: -left, top: -bottom, bottom: -top)
  return Float(min(1, max(0, area)))
}
