//
//  DrawingContext+Primitives.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-11-12.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension DrawingContext {

  @discardableResult
  mutating func fillRect(_ rect: PixelRect) -> Bool {
    guard let intersection = contextFrame.intersection(rect) else { return true }

    let alpha = UInt8(fillColor.alpha)
    guard alpha > 0 else { return true }

    guard alpha < 255 else {
      for y in intersection.minY..<intersection.maxY {
        guard writeOpaqueSpan(y: y, from: intersection.minX, to: intersection.maxX, color: fillColor)
        else { return false }
      }
      return true
    }

    for y in intersection.minY..<intersection.maxY {
      guard
        writeBlendedSpan(
          y: y, from: intersection.minX, to: intersection.maxX, color: fillColor, effectiveAlpha: alpha)
      else { return false }
    }
    return true
  }

  mutating func fillRect(_ rect: DrawingRect) -> Bool {
    guard
      rect.minX.isFinite,
      rect.minY.isFinite,
      rect.maxX.isFinite,
      rect.maxY.isFinite,
      let clipped = rect.intersection(drawingFrame),
      clipped.minX < clipped.maxX,
      clipped.minY < clipped.maxY
    else { return true }

    let horizontal = AxisCoverage(from: clipped.minX, to: clipped.maxX)
    let vertical = AxisCoverage(from: clipped.minY, to: clipped.maxY)

    // Calculate coverage for one class of rows.
    func rowCoverage(_ factor: Float) -> (leading: UInt8, interior: UInt8, trailing: UInt8) {
      let leading =
        horizontal.leading.map {
          ($0.coverage * factor).unitQuantized8
        } ?? 0

      let trailing =
        horizontal.trailing.map {
          ($0.coverage * factor).unitQuantized8
        } ?? 0

      return (leading, factor.unitQuantized8, trailing)
    }

    // Quantise each distinct coverage value only once.
    let middle = rowCoverage(1)

    // Top fractional row, if present.
    if let top = vertical.leading, top.index < contextSize.height {
      let coverage = rowCoverage(top.coverage)

      guard
        paintRectangleRow(
          y: top.index,
          horizontal: horizontal,
          leadingCoverage: coverage.leading,
          interiorCoverage: coverage.interior,
          trailingCoverage: coverage.trailing
        )
      else { return false }
    }

    // Fully covered interior rows.
    for y in vertical.interior.clamped(to: 0..<contextSize.height) {
      guard
        paintRectangleRow(
          y: y,
          horizontal: horizontal,
          leadingCoverage: middle.leading,
          interiorCoverage: middle.interior,
          trailingCoverage: middle.trailing
        )
      else { return false }
    }

    // Bottom fractional row, if present.
    if let bottom = vertical.trailing, bottom.index < contextSize.height {
      let coverage = rowCoverage(bottom.coverage)

      guard
        paintRectangleRow(
          y: bottom.index,
          horizontal: horizontal,
          leadingCoverage: coverage.leading,
          interiorCoverage: coverage.interior,
          trailingCoverage: coverage.trailing
        )
      else { return false }
    }
    return true
  }

  /// Draws a one-pixel-wide raster line between two pixel coordinates.
  /// Both endpoints are included. Pixels outside the context are ignored.
  @discardableResult
  mutating func strokeLine(from start: PixelPoint, to end: PixelPoint) -> Bool {
    guard checkDeadline() else { return false }
    guard strokeColor.alpha > 0 else { return true }

    var x0 = start.x
    var y0 = start.y
    let x1 = end.x
    let y1 = end.y

    let dx = abs(x1 - x0)
    let sx = x0 < x1 ? 1 : -1
    let dy = -abs(y1 - y0)
    let sy = y0 < y1 ? 1 : -1

    var error = dx + dy

    while true {
      _ = blendPixel(at: PixelPoint(x: x0, y: y0), to: strokeColor)

      if x0 == x1 && y0 == y1 {
        break
      }

      let e2 = 2 * error

      if e2 >= dy {
        error += dy
        x0 += sx
      }

      if e2 <= dx {
        error += dx
        y0 += sy
      }
    }
    return true
  }
}

struct AxisCoverage {
  let leading: (index: Int, coverage: Float)?
  let interior: Range<Int>
  let trailing: (index: Int, coverage: Float)?

  init(from start: Float, to end: Float) {
    precondition(start.isFinite && end.isFinite && start < end)

    let first = Int(start.rounded(.down))
    let afterLast = Int(end.rounded(.up))

    // Entire interval occupies one pixel.
    if afterLast == first + 1 {
      let coverage = end - start

      if coverage == 1 {
        leading = nil
        interior = first..<afterLast
        trailing = nil
      } else if start == Float(first) {
        leading = nil
        interior = first..<first
        trailing = (first, coverage)
      } else {
        leading = (first, coverage)
        interior = first..<first
        trailing = nil
      }
      return
    }

    // Fractional leading pixel.
    if start > Float(first) {
      leading = (first, Float(first + 1) - start)
    } else {
      leading = nil
    }

    // Fractional trailing pixel.
    if end < Float(afterLast) {
      trailing = (afterLast - 1, end - Float(afterLast - 1))
    } else {
      trailing = nil
    }

    let interiorStart = first + (leading == nil ? 0 : 1)
    let interiorEnd = afterLast - (trailing == nil ? 0 : 1)
    interior = interiorStart..<interiorEnd
  }
}

extension DrawingContext {
  /// Paints a coverage sample after the caller has checked the row deadline.
  @inline(__always)
  mutating func paintCoveragePixel(
    at point: PixelPoint,
    to color: PixelColor32,
    coverage: UInt8
  ) -> Bool {
    guard coverage > 0, color.alpha > 0 else { return true }

    let alpha = UInt8((UInt32(coverage) * UInt32(color.alpha) + 127) / 255)

    guard alpha > 0 else { return true }

    if alpha == 255 {
      return setPixel(at: point, to: color)
    }

    return blendPixel(at: point, to: color, withAlpha: alpha)
  }

  private mutating func paintRectangleRow(
    y: Int,
    horizontal: AxisCoverage,
    leadingCoverage: UInt8,
    interiorCoverage: UInt8,
    trailingCoverage: UInt8
  ) -> Bool {
    let color = fillColor

    let interior = horizontal.interior.clamped(to: 0..<contextSize.width)
    if !interior.isEmpty {
      guard
        paintSpan(
          y: y,
          from: interior.lowerBound,
          to: interior.upperBound,
          coverage: interiorCoverage,
          operation: .fill
        )
      else { return false }
    } else {
      guard checkDeadline() else { return false }
    }

    if let leading = horizontal.leading, leading.index < contextSize.width {
      guard
        paintCoveragePixel(
          at: PixelPoint(x: leading.index, y: y),
          to: color,
          coverage: leadingCoverage
        )
      else { return false }
    }

    if let trailing = horizontal.trailing, trailing.index < contextSize.width {
      guard
        paintCoveragePixel(
          at: PixelPoint(x: trailing.index, y: y),
          to: color,
          coverage: trailingCoverage
        )
      else { return false }
    }

    return true
  }
}
