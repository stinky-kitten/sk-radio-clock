// Tangent and single-chord coverage share the same two arc endpoints.
enum CircleCellBoundary {
  case empty
  case full
  case arc(chordMidpoint: DrawingPoint, arcMidpoint: DrawingPoint)
}

/// Nil means that a single line cannot represent the local arc.
func circleCellBoundary(at pixel: PixelPoint, centre: DrawingPoint, radius: Float) -> CircleCellBoundary? {
  let left = Float(pixel.x) - centre.x
  let top = Float(pixel.y) - centre.y
  let right = left + 1
  let bottom = top + 1
  let nearX = max(left, -right, 0)
  let nearY = max(top, -bottom, 0)
  let farX = max(abs(left), abs(right))
  let farY = max(abs(top), abs(bottom))
  let squared = radius * radius
  if nearX * nearX + nearY * nearY >= squared { return .empty }
  if farX * farX + farY * farY <= squared { return .full }

  var first = DrawingPoint.zero
  var second = DrawingPoint.zero
  var count = 0
  func add(_ x: Float, _ y: Float) {
    guard count < 3 else { return }
    let point = DrawingPoint(x: x, y: y)
    func matches(_ other: DrawingPoint) -> Bool {
      abs(other.x - x) <= 1e-6 && abs(other.y - y) <= 1e-6
    }
    if count >= 1 && matches(first) || count >= 2 && matches(second) { return }
    if count == 0 { first = point } else if count == 1 { second = point }
    count += 1
  }

  for x in [left, right] as InlineArray<2, Float> {
    let delta = (radius - abs(x)) * (radius + abs(x))
    guard delta >= 0 else { continue }
    let root = delta.squareRoot()
    if top <= root && root <= bottom { add(x, root) }
    if top <= -root && -root <= bottom { add(x, -root) }
  }
  for y in [top, bottom] as InlineArray<2, Float> {
    let delta = (radius - abs(y)) * (radius + abs(y))
    guard delta >= 0 else { continue }
    let root = delta.squareRoot()
    if left <= root && root <= right { add(root, y) }
    if left <= -root && -root <= right { add(-root, y) }
  }

  // A disk wholly contained in the pixel has no edge intersections.
  guard count == 2 else { return nil }
  let midX = (first.x + second.x) * 0.5
  let midY = (first.y + second.y) * 0.5
  let length = (midX * midX + midY * midY).squareRoot()
  guard length > 0 else { return nil }
  let arcX = midX * (radius / length)
  let arcY = midY * (radius / length)
  // Reject a major arc, or ambiguous geometry, when the minor midpoint
  // lies outside the cell or the opposite midpoint lies inside it.
  guard left <= arcX, arcX <= right, top <= arcY, arcY <= bottom,
    !(left <= -arcX && -arcX <= right && top <= -arcY && -arcY <= bottom)
  else { return nil }

  return .arc(
    chordMidpoint: DrawingPoint(x: midX, y: midY), arcMidpoint: DrawingPoint(x: arcX, y: arcY))
}

func tangentCircleCoverage(at pixel: PixelPoint, centre: DrawingPoint, radius: Float) -> Float? {
  switch circleCellBoundary(at: pixel, centre: centre, radius: radius) {
  case .empty: return 0
  case .full: return 1
  case .arc(let chord, let arc):
    let point = DrawingPoint(x: centre.x + arc.x, y: centre.y + arc.y)
    return lineCoverage(at: pixel, through: point, normal: DrawingPoint(x: -chord.x, y: -chord.y))
  case nil: return nil
  }
}
