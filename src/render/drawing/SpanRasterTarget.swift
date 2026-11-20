//
//  SpanRasterTarget.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-21.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

enum DrawingOperation: Sendable {
  case fill
  case stroke
}

/// Paints spans preclipped by the caller. The RGB context honours its drawing deadline.
protocol SpanRasterTarget {
  var contextSize: PixelSize { get }

  /// Paints a half-open span with the current paint. Requires
  /// `0 <= y < contextSize.height` and `0 <= from <= to <= contextSize.width`.
  /// An empty span may still check the deadline and return `false` on expiry.
  mutating func paintSpan(y: Int, from left: Int, to right: Int) -> Bool
}

/// Applies the selected colour and coverage to spans preclipped by the caller.
/// Painters check the drawing deadline before significant work.
protocol CoverageSpanRasterTarget {
  var contextSize: PixelSize { get }

  /// Paints consecutive pixels using one borrowed coverage value per pixel.
  /// Requires `0 <= y < contextSize.height`,
  /// `0 <= from <= contextSize.width` and `coverage.count <= contextSize.width - from`.
  /// Returns `false` if the deadline check fails.
  mutating func paintSpan(
    y: Int,
    from x: Int,
    coverage: Span<UInt8>,
    operation: DrawingOperation
  ) -> Bool

  /// Paints a half-open span with constant coverage. Requires
  /// `0 <= y < contextSize.height` and `0 <= from <= to <= contextSize.width`.
  /// An empty span may still check the deadline and return `false` on expiry.
  mutating func paintSpan(
    y: Int,
    from x: Int,
    to endX: Int,
    coverage: UInt8,
    operation: DrawingOperation
  ) -> Bool
}

extension SpanRasterTarget {

  /// Fills a convex quadrilateral, with vertices in boundary order.
  /// Shared edges follow a half-open rule. Geometry must be finite.
  mutating func fillQuad(_ quad: DrawingQuad) -> Bool {
    var minY = quad.vertices[0].y
    var maxY = quad.vertices[0].y
    for vertex in quad.vertices {
      minY = min(minY, vertex.y)
      maxY = max(maxY, vertex.y)
    }

    let firstRow = clippedPixelBound(minY.rounded(.up), limit: contextSize.height)
    let endRow = clippedPixelBound(maxY.rounded(.up), limit: contextSize.height)

    for y in firstRow..<endRow {
      let sampleY = Float(y)
      var minX = Float.infinity
      var maxX = -Float.infinity

      for edgeIndex in 0..<4 {
        let a = quad.vertices[edgeIndex]
        let b = quad.vertices[(edgeIndex + 1) % 4]

        guard sampleY >= min(a.y, b.y), sampleY < max(a.y, b.y) else { continue }
        let intersectionX =
          a.x + (sampleY - a.y) * (b.x - a.x) / (b.y - a.y)
        minX = min(minX, intersectionX)
        maxX = max(maxX, intersectionX)
      }
      guard minX < maxX else { continue }

      let firstColumn = clippedPixelBound(minX.rounded(.up), limit: contextSize.width)
      let endColumn = clippedPixelBound(maxX.rounded(.up), limit: contextSize.width)

      guard paintSpan(y: y, from: firstColumn, to: endColumn) else { return false }
    }
    return true
  }

  /// Fills a fractional circle without rounding its centre or radius.
  @discardableResult
  mutating func fillCircle(centre: DrawingPoint, radius: Float) -> Bool {
    guard radius > 0 else { return true }

    let firstRow = clippedPixelBound((centre.y - radius).rounded(.up), limit: contextSize.height)
    let endRow = clippedEnd(after: centre.y + radius, limit: contextSize.height)

    // The guard can be removed after input validation, but it is a useful sanity check for now.
    guard firstRow < endRow else { return true }
    for y in firstRow..<endRow {
      let deltaY = Float(y) - centre.y
      let halfChordWidth = max(0, radius * radius - deltaY * deltaY).squareRoot()
      let minX = centre.x - halfChordWidth
      let maxX = centre.x + halfChordWidth

      let firstColumn = clippedPixelBound(minX.rounded(.up), limit: contextSize.width)
      let endColumn = clippedEnd(after: maxX, limit: contextSize.width)
      guard paintSpan(y: y, from: firstColumn, to: endColumn) else { return false }
    }
    return true
  }
}

private let minimumTangentCircleRadius: Float = 24

extension CoverageSpanRasterTarget {
  /// Fills a disk in destination drawing coordinates. Pixel `(x, y)` occupies
  /// `[x, x + 1) × [y, y + 1)`. Convert a pixel address with `drawingCentre`
  /// when centring the disk on that pixel.
  /// Uses a tangent for boundary cells at radii of 24 pixels or greater,
  /// with refined-chord coverage for smaller disks and ambiguous arcs.
  /// The caller supplies reusable scratch with at least `contextSize.width` bytes.
  mutating func fillAntialiasedCircle(
    centre: DrawingPoint, radius: Float, coverageRow: inout MutableSpan<UInt8>
  ) -> Bool {
    guard centre.x.isFinite, centre.y.isFinite, radius.isFinite, radius > 0 else { return true }
    let x = centre.x
    let y = centre.y
    let r = radius
    let width = contextSize.width
    let height = contextSize.height

    func halfChord(at distance: Float) -> Float {
      max(0, (r - distance) * (r + distance)).squareRoot()
    }

    let firstRow = clippedPixelBound((y - r).rounded(.down), limit: height)
    let endRow = clippedPixelBound((y + r).rounded(.up), limit: height)
    guard firstRow < endRow, x + r > 0, clippedPixelBound((x - r).rounded(.down), limit: width) < width else {
      return true
    }
    precondition(coverageRow.count >= width)

    let useTangent = radius >= minimumTangentCircleRadius
    for row in firstRow..<endRow {
      let top = Float(row) - y
      let bottom = top + 1
      let outerHalfChord = halfChord(at: max(top, -bottom, 0))
      guard outerHalfChord > 0 else { continue }
      let start = clippedPixelBound((x - outerHalfChord).rounded(.down), limit: width)
      let end = clippedPixelBound((x + outerHalfChord).rounded(.up), limit: width)
      guard start < end else { continue }

      // The narrower chord at the far edge of the row bounds every cell
      // whose four corners are in the disk.
      let innerHalfChord = halfChord(at: max(abs(top), abs(bottom)))
      let fullStart = clippedPixelBound((x - innerHalfChord).rounded(.up), limit: width)
      let fullEnd = clippedPixelBound((x + innerHalfChord).rounded(.down), limit: width)
      if start >= fullStart, end <= fullEnd {
        guard paintSpan(y: row, from: start, to: end, coverage: 255, operation: .fill) else { return false }
        continue
      }

      for column in start..<end {
        if column >= fullStart, column < fullEnd {
          coverageRow[column - start] = 255
        } else {
          let pixel = PixelPoint(x: column, y: row)
          let tangent = useTangent ? tangentCircleCoverage(at: pixel, centre: centre, radius: radius) : nil
          coverageRow[column - start] =
            (tangent ?? diskCoverage(at: pixel, centre: centre, radius: radius))
            .unitQuantized8
        }
      }

      // One paint call means expiry cannot split the interior and edges of a row.
      guard paintSpan(y: row, from: start, coverage: coverageRow.span.extracting(first: end - start), operation: .fill)
      else { return false }
    }
    return true
  }
}

func clippedPixelBound(_ rounded: Float, limit: Int) -> Int {
  guard rounded > 0 else { return 0 }
  // Keep the destination limit exact and saturate coordinates outside Int's range.
  return min(Int(exactly: rounded) ?? limit, limit)
}

private func clippedEnd(after coordinate: Float, limit: Int) -> Int {
  guard coordinate >= 0 else { return 0 }
  let last = clippedPixelBound(coordinate.rounded(.down), limit: limit)
  return last < limit ? last + 1 : limit
}
