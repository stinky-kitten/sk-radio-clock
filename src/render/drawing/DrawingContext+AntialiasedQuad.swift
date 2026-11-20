private struct QuadEdge {
  let point: DrawingPoint
  let normal: DrawingPoint
}

extension DrawingContext {
  /// Fills a convex quadrilateral in unit-cell drawing coordinates.
  /// Accepts a finite, strictly convex perimeter in either winding.
  /// Invalid, degenerate and wholly clipped quads complete without painting.
  /// The caller supplies reusable scratch with at least `contextSize.width` bytes.
  /// Returns `false` if a row's deadline check fails.
  mutating func fillAntialiasedQuad(_ quad: DrawingQuad, coverageRow: inout MutableSpan<UInt8>) -> Bool {
    let color = fillColor
    guard color.alpha > 0 else { return true }

    var minX = Float.infinity
    var minY = Float.infinity
    var maxX = -Float.infinity
    var maxY = -Float.infinity
    var edges = InlineArray<4, QuadEdge>(repeating: QuadEdge(point: .zero, normal: .zero))
    for index in edges.indices {
      let a = quad.vertices[index]
      let b = quad.vertices[(index + 1) % 4]
      guard a.x.isFinite, a.y.isFinite else { return true }
      let dx = b.x - a.x
      let dy = b.y - a.y
      let scale = max(abs(dx), abs(dy))
      guard dx.isFinite, dy.isFinite, scale > 0 else { return true }
      edges[index] = QuadEdge(point: a, normal: DrawingPoint(x: -dy / scale, y: dx / scale))
      minX = min(minX, a.x)
      minY = min(minY, a.y)
      maxX = max(maxX, a.x)
      maxY = max(maxY, a.y)
    }

    var winding: Float = 0
    for index in edges.indices {
      let a = edges[index].normal
      let b = edges[(index + 1) % 4].normal
      let turn = a.x * b.y - a.y * b.x
      guard turn != 0, index == 0 || turn.sign == winding.sign else { return true }
      winding = turn
    }
    if winding < 0 {
      for index in edges.indices {
        let edge = edges[index]
        edges[index] = QuadEdge(point: edge.point, normal: DrawingPoint(x: -edge.normal.x, y: -edge.normal.y))
      }
    }

    let width = contextSize.width
    let firstRow = clippedPixelBound(minY.rounded(.down), limit: contextSize.height)
    let endRow = clippedPixelBound(maxY.rounded(.up), limit: contextSize.height)
    guard firstRow < endRow, maxX > 0, clippedPixelBound(minX.rounded(.down), limit: width) < width
    else { return true }
    precondition(coverageRow.count >= width)

    for y in firstRow..<endRow {
      var outerLeft = minX
      var outerRight = maxX
      var innerLeft = minX
      var innerRight = maxX
      var fullHeight = true

      // For each half-plane, its most permissive x bound over the strip
      // can contain boundary cells. Its strictest bound contains whole cells.
      for edge in edges {
        let nx = edge.normal.x
        let ny = edge.normal.y
        let top = ny * (Float(y) - edge.point.y)
        let bottom = ny * (Float(y) - (edge.point.y - 1))
        let near = min(top, bottom)
        let far = max(top, bottom)
        if nx > 0 {
          outerLeft = max(outerLeft, edge.point.x - far / nx)
          innerLeft = max(innerLeft, edge.point.x - near / nx)
        } else if nx < 0 {
          outerRight = min(outerRight, edge.point.x - far / nx)
          innerRight = min(innerRight, edge.point.x - near / nx)
        } else {
          fullHeight = fullHeight && near >= 0
        }
      }
      guard outerLeft < outerRight else { continue }
      let start = clippedPixelBound(outerLeft.rounded(.down), limit: width)
      let end = clippedPixelBound(outerRight.rounded(.up), limit: width)
      guard start < end else { continue }

      let fullStart = max(start, clippedPixelBound(innerLeft.rounded(.up), limit: end))
      let fullEnd = fullHeight ? max(fullStart, clippedPixelBound(innerRight.rounded(.down), limit: end)) : fullStart
      let boundary: InlineArray<2, Range<Int>> = [start..<fullStart, fullEnd..<end]
      for columns in boundary {
        for x in columns {
          coverageRow[x] = quadCellCoverage(at: PixelPoint(x: x, y: y), edges: edges).unitQuantized8
        }
      }

      // Prepare coverage before the row's only checkpoint. The interior
      // writer takes that checkpoint when there is a full span.
      if fullStart < fullEnd {
        guard paintSpan(y: y, from: fullStart, to: fullEnd) else { return false }
      } else {
        guard checkDeadline() else { return false }
      }
      for columns in boundary {
        for x in columns {
          guard paintCoveragePixel(at: PixelPoint(x: x, y: y), to: color, coverage: coverageRow[x])
          else { return false }
        }
      }
    }
    return true
  }
}

private func quadCellCoverage(at pixel: PixelPoint, edges: InlineArray<4, QuadEdge>) -> Float {
  var active = 0
  for index in edges.indices {
    let edge = edges[index]
    let nx = edge.normal.x
    let ny = edge.normal.y
    let left = Float(pixel.x) - edge.point.x
    let right = Float(pixel.x) - (edge.point.x - 1)
    let top = Float(pixel.y) - edge.point.y
    let bottom = Float(pixel.y) - (edge.point.y - 1)
    let far = nx * (nx < 0 ? left : right) + ny * (ny < 0 ? top : bottom)
    guard far > 0 else { return 0 }
    let near = nx * (nx < 0 ? right : left) + ny * (ny < 0 ? bottom : top)
    if near < 0 { active |= 1 << index }
  }
  guard active != 0 else { return 1 }
  let first = active.trailingZeroBitCount
  if active == 1 << first {
    let edge = edges[first]
    return lineCoverage(at: pixel, through: edge.point, normal: edge.normal)
  }
  return clippedQuadCellArea(at: pixel, edges: edges, active: active)
}

private func clippedQuadCellArea(at pixel: PixelPoint, edges: InlineArray<4, QuadEdge>, active: Int) -> Float {
  // Clipping a square against four half-planes needs at most eight vertices.
  var polygon = InlineArray<8, DrawingPoint>(repeating: .zero)
  polygon[1] = DrawingPoint(x: 1, y: 0)
  polygon[2] = DrawingPoint(x: 1, y: 1)
  polygon[3] = DrawingPoint(x: 0, y: 1)
  var clipped = InlineArray<8, DrawingPoint>(repeating: .zero)
  var count = 4

  for index in edges.indices where active & (1 << index) != 0 {
    let edge = edges[index]
    let nx = edge.normal.x
    let ny = edge.normal.y
    let left = Float(pixel.x) - edge.point.x
    let top = Float(pixel.y) - edge.point.y
    func distance(_ point: DrawingPoint) -> Float {
      nx * (left + point.x) + ny * (top + point.y)
    }

    var written = 0
    var previous = polygon[count - 1]
    var previousDistance = distance(previous)
    for vertex in 0..<count {
      let current = polygon[vertex]
      let currentDistance = distance(current)
      if (previousDistance < 0 && currentDistance > 0) || (previousDistance > 0 && currentDistance < 0) {
        let t = previousDistance / (previousDistance - currentDistance)
        clipped[written] = DrawingPoint(
          x: previous.x + t * (current.x - previous.x), y: previous.y + t * (current.y - previous.y))
        written += 1
      }
      if currentDistance >= 0 {
        clipped[written] = current
        written += 1
      }
      previous = current
      previousDistance = currentDistance
    }
    guard written >= 3 else { return 0 }
    count = written
    swap(&polygon, &clipped)
  }

  // Measure in cell-local coordinates, relative to a vertex to limit cancellation.
  let origin = polygon[0]
  var twiceArea: Float = 0
  for index in 1..<(count - 1) {
    let a = polygon[index]
    let b = polygon[index + 1]
    twiceArea += (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
  }
  return min(1, max(0, twiceArea * 0.5))
}
