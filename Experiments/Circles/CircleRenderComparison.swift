//
//  CircleRenderComparison.swift
//  sk-radio-clock
//
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

#if SWIFT_PACKAGE
  @testable import RadioClockLogic
#endif

enum CircleRenderComparison {
  static let radius: Float = 4

  static func centres(at timeUs: UInt64) -> (analytical: DrawingPoint, chord: DrawingPoint) {
    func bounce(travel: UInt64, speed: UInt64) -> Float {
      // Use exact 1/256-pixel positions so the lane offset stays exact in Float.
      let extent = travel * 256
      let period = 2 * extent
      let ticks = (timeUs % (period * 1_000_000)) * speed * 256 / 1_000_000
      let phase = ticks % period
      return Float(min(phase, period - phase)) / 256
    }

    let x = radius + 1 + bounce(travel: 22, speed: 5)
    let y = radius + bounce(travel: 56, speed: 8)
    return (DrawingPoint(x: x, y: y), DrawingPoint(x: x + 32, y: y))
  }

  static func paint<T: CoverageSpanRasterTarget>(into target: inout T, at timeUs: UInt64) -> Bool {
    precondition(target.contextSize == PixelSize(width: 64, height: 64))
    let (analytical, chord) = centres(at: timeUs)
    var row: InlineArray<64, UInt8> = .init(repeating: 0)
    var scratch = row.mutableSpan

    let left = Int((analytical.x - radius).rounded(.down))
    let right = Int((analytical.x + radius).rounded(.up))
    let top = Int((analytical.y - radius).rounded(.down))
    let bottom = Int((analytical.y + radius).rounded(.up))
    for y in top..<bottom {
      for x in left..<right {
        scratch[x - left] =
          analyticalDiskCoverage(
            at: PixelPoint(x: x, y: y), centre: analytical, radius: radius
          ).unitQuantized8
      }
      guard target.paintSpan(y: y, from: left, coverage: scratch.span.extracting(first: right - left), operation: .fill)
      else { return false }
    }

    return target.fillRefinedChordCircle(centre: chord, radius: radius, coverageRow: &scratch)
  }
}
