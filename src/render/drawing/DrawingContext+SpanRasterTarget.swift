//
//  DrawingContext+SpanRasterTarget.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-21.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension DrawingContext: SpanRasterTarget {
  mutating func paintSpan(y: Int, from left: Int, to right: Int) -> Bool {
    let alpha = UInt8(fillColor.alpha)
    guard alpha > 0 else { return true }

    if alpha == 255 {
      return writeOpaqueSpan(y: y, from: left, to: right, color: fillColor)
    }

    return writeBlendedSpan(y: y, from: left, to: right, color: fillColor, effectiveAlpha: alpha)
  }
}

extension DrawingContext: CoverageSpanRasterTarget {
  mutating func paintSpan(
    y: Int,
    from x: Int,
    to endX: Int,
    coverage: UInt8,
    operation: DrawingOperation
  ) -> Bool {
    guard coverage > 0 else { return true }

    let color: PixelColor32
    switch operation {
    case .fill:
      color = fillColor
    case .stroke:
      color = strokeColor
    }

    guard color.alpha > 0 else { return true }

    let effectiveAlpha = UInt8((UInt32(coverage) * UInt32(color.alpha) + 127) / 255)
    guard effectiveAlpha > 0 else { return true }

    if effectiveAlpha == 255 {
      return writeOpaqueSpan(y: y, from: x, to: endX, color: color)
    }

    return writeBlendedSpan(y: y, from: x, to: endX, color: color, effectiveAlpha: effectiveAlpha)
  }

  mutating func paintSpan(
    y: Int,
    from x: Int,
    coverage: Span<UInt8>,
    operation: DrawingOperation
  ) -> Bool {
    guard !coverage.isEmpty else { return true }

    let color: PixelColor32
    switch operation {
    case .fill:
      color = fillColor
    case .stroke:
      color = strokeColor
    }

    guard color.alpha > 0 else { return true }
    guard checkDeadline() else { return false }

    for offset in 0..<coverage.count {
      let alpha = UInt8((UInt32(coverage[offset]) * UInt32(color.alpha) + 127) / 255)

      guard alpha > 0 else { continue }

      let point = PixelPoint(x: x + offset, y: y)

      if alpha == 255 {
        _ = setPixel(at: point, to: color)
      } else {
        _ = blendPixel(at: point, to: color, withAlpha: alpha)
      }
    }

    return true
  }
}
