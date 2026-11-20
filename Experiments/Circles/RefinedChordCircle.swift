#if SWIFT_PACKAGE
  @testable import RadioClockLogic
#endif

extension CoverageSpanRasterTarget {
  /// Fills a disk in destination drawing coordinates. Pixel `(x, y)` occupies
  /// `[x, x + 1) × [y, y + 1)`. Convert a pixel address with `drawingCentre`
  /// when centring the disk on that pixel.
  /// The caller supplies reusable scratch with at least `contextSize.width` bytes.
  mutating func fillRefinedChordCircle(
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
        coverageRow[column - start] =
          (column >= fullStart && column < fullEnd)
          ? 255 : diskCoverage(at: PixelPoint(x: column, y: row), centre: centre, radius: radius).unitQuantized8
      }

      // One paint call means expiry cannot split the interior and edges of a row.
      guard paintSpan(y: row, from: start, coverage: coverageRow.span.extracting(first: end - start), operation: .fill)
      else { return false }
    }
    return true
  }
}
