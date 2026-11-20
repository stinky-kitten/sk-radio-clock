//
//  LineCoverage.swift
//  sk-radio-clock
//
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

/// Covers the side pointed to by `normal` from `point` on the line.
/// The normal need not be unit length. Invalid or zero normals cover nothing.
/// Pixel `(x, y)` occupies `[x, x + 1) × [y, y + 1)` in drawing coordinates.
func lineCoverage(at pixel: PixelPoint, through point: DrawingPoint, normal: DrawingPoint) -> Float {
  let nx = normal.x
  let ny = normal.y
  let major = max(abs(nx), abs(ny))
  guard nx.isFinite, ny.isFinite, major > 0, point.x.isFinite, point.y.isFinite else { return 0 }

  // Leave headroom for two corner products and their sum, including Int pixel
  // coordinates. Lift very small normals before their products lose precision.
  let rescale = major < 0x1p-63 || max(major, abs(point.x), abs(point.y)) > 0x1p62
  let majorDepth: Float = rescale ? 0.5 : major
  func dot(_ x: Float, _ y: Float) -> Float {
    guard rescale else { return nx * x + ny * y }

    // Scale each product to units of half the major component. Multiplying
    // a small component first preserves its contribution over long distances.
    func scaledProduct(_ component: Float, _ distance: Float) -> Float {
      if major > 1, abs(component) <= 1 {
        return (component * distance / major) * 0.5
      }
      return (component / major * distance) * 0.5
    }
    return scaledProduct(nx, x) + scaledProduct(ny, y)
  }

  // Reflect axes with negative normal components so the line value increases
  // from the lowest corner toward the diagonally opposite corner.
  let x = Float(pixel.x) - point.x
  let y = Float(pixel.y) - point.y
  let right = Float(pixel.x) - (point.x - 1)
  let bottom = Float(pixel.y) - (point.y - 1)
  let depth = -dot(nx < 0 ? right : x, ny < 0 ? bottom : y)
  guard depth > 0 else { return 1 }

  let minor = min(abs(nx), abs(ny))
  let minorDepth = rescale ? (minor / major) * 0.5 : minor
  let area: Float
  if depth < minorDepth {
    // Adjacent edges at the low corner bound the uncovered triangle.
    area = 1 - 0.5 * (depth / majorDepth) * (depth / minorDepth)
  } else {
    // Evaluate the far corner directly to retain small grazing intersections.
    let farDepth = dot(nx > 0 ? right : x, ny > 0 ? bottom : y)
    guard farDepth > 0 else { return 0 }
    if farDepth < minorDepth {
      // Adjacent edges at the high corner bound the covered triangle.
      area = 0.5 * (farDepth / majorDepth) * (farDepth / minorDepth)
    } else {
      // Opposite edges, including axis-aligned lines where minorDepth is zero.
      area = (farDepth - 0.5 * minorDepth) / majorDepth
    }
  }
  return min(1, max(0, area))
}
