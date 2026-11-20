//
//  DiskCoverage.swift
//  sk-radio-clock
//
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

/// Approximates disk area inside the unit cell with `pixel` as its minimum corner.
/// The centre is in destination drawing coordinates. Invalid disks have zero coverage.
func diskCoverage(at pixel: PixelPoint, centre: DrawingPoint, radius: Float) -> Float {
  guard centre.x.isFinite, centre.y.isFinite, radius.isFinite, radius > 0 else { return 0 }

  let left = Float(pixel.x) - centre.x
  let top = Float(pixel.y) - centre.y
  let right = left + 1
  let bottom = top + 1

  func halfChordSquared(at offset: Float) -> Float {
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
    return .pi * radiusSquared
  }

  // Reflect the pieces of the cell into the positive quadrant, where the
  // right edge of the disk decreases monotonically with increasing y.
  func quadrantArea(left: Float, right: Float, top: Float, bottom: Float) -> Float {
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

    // Replace the arc with its chord. A short chord can use an upper bound
    // on the segment area without calculating the sagitta.
    let dx = startX - endX
    let trapezoid = dy * (max(0, startX - left) + max(0, endX - left)) / 2
    var halfLengthSquared = (dx * dx + dy * dy) / 4
    let areaLimit: Float = 1 / 255
    let shortChordLimit = radius * (areaLimit / 2)
    guard halfLengthSquared * halfLengthSquared * halfLengthSquared > shortChordLimit * shortChordLimit else {
      return fullArea + trapezoid
    }

    // Bisect longer arcs. Equal sub-arcs have equal midpoint triangles,
    // so we can add their areas without storing vertices or walking edges again.
    var area = fullArea + trapezoid
    var chordCount: Float = 1
    for _ in 0..<4 {
      let halfLength = halfLengthSquared.squareRoot()
      let sagitta = halfLengthSquared / (radius + max(0, halfChordSquared(at: halfLength)).squareRoot())
      let triangles = chordCount * halfLength * sagitta
      guard 2 * triangles > areaLimit else { break }
      area += triangles
      halfLengthSquared = (halfLengthSquared + sagitta * sagitta) / 4
      chordCount *= 2
    }
    return area
  }

  let area =
    quadrantArea(left: left, right: right, top: top, bottom: bottom)
    + quadrantArea(left: -right, right: -left, top: top, bottom: bottom)
    + quadrantArea(left: left, right: right, top: -bottom, bottom: -top)
    + quadrantArea(left: -right, right: -left, top: -bottom, bottom: -top)
  return min(1, max(0, area))
}
