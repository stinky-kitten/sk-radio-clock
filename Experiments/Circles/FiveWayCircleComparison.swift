//
//  FiveWayCircleComparison.swift
//  sk-radio-clock
//
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

#if SWIFT_PACKAGE
  @testable import RadioClockLogic
#endif

enum FiveWayCircleComparison {
  static let radius: Float = 4
  private static let holdUs: UInt64 = 10_000_000

  struct Fallbacks {
    var singleChord: UInt64 = 0
    var tangent: UInt64 = 0
  }

  static func positionIndex(at elapsedUs: UInt64) -> Int {
    Int((elapsedUs / holdUs) % 16)
  }

  static func quarterOffsets(for index: Int) -> (x: Int, y: Int) {
    (index % 4, index / 4)
  }

  static func localCentre(at elapsedUs: UInt64) -> DrawingPoint {
    let offsets = quarterOffsets(for: positionIndex(at: elapsedUs))
    return DrawingPoint(x: 10 + Float(offsets.x) * 0.25, y: 15 + Float(offsets.y) * 0.25)
  }

  static func paint<T: CoverageSpanRasterTarget & SpanRasterTarget>(
    into target: inout T, at timeUs: UInt64, fallbacks: inout Fallbacks
  ) -> Bool {
    let local = localCentre(at: timeUs)
    var row: InlineArray<64, UInt8> = .init(repeating: 0)
    var scratch = row.mutableSpan
    for lane in 0..<5 {
      let centre = DrawingPoint(x: local.x + Float(lane % 3 * 21), y: local.y + Float(lane / 3 * 32))
      switch lane {
      case 1:
        guard target.fillRefinedChordCircle(centre: centre, radius: radius, coverageRow: &scratch) else { return false }
      case 4:
        let binaryCentre = DrawingPoint(x: centre.x - 0.5, y: centre.y - 0.5)
        guard target.fillCircle(centre: binaryCentre, radius: radius) else { return false }
      default:
        let left = Int((centre.x - radius).rounded(.down))
        let right = Int((centre.x + radius).rounded(.up))
        let top = Int((centre.y - radius).rounded(.down))
        let bottom = Int((centre.y + radius).rounded(.up))
        for y in top..<bottom {
          for x in left..<right {
            let pixel = PixelPoint(x: x, y: y)
            let coverage: Float
            if lane == 0 {
              coverage = analyticalDiskCoverage(at: pixel, centre: centre, radius: radius)
            } else if let linear = linearCoverage(at: pixel, centre: centre, radius: radius, tangent: lane == 3) {
              coverage = linear
            } else {
              if lane == 2 { fallbacks.singleChord &+= 1 } else { fallbacks.tangent &+= 1 }
              coverage = analyticalDiskCoverage(at: pixel, centre: centre, radius: radius)
            }
            scratch[x - left] = coverage.unitQuantized8
          }
          guard
            target.paintSpan(
              y: y, from: left, coverage: scratch.span.extracting(first: right - left), operation: .fill)
          else { return false }
        }
      }
    }
    return true
  }

  /// Nil means that a single line cannot represent the local arc.
  static func linearCoverage(at pixel: PixelPoint, centre: DrawingPoint, radius: Float, tangent: Bool) -> Float? {
    if tangent {
      return tangentCircleCoverage(at: pixel, centre: centre, radius: radius)
    }
    switch circleCellBoundary(at: pixel, centre: centre, radius: radius) {
    case .empty: return 0
    case .full: return 1
    case .arc(let chord, _):
      let point = DrawingPoint(x: centre.x + chord.x, y: centre.y + chord.y)
      return lineCoverage(at: pixel, through: point, normal: DrawingPoint(x: -chord.x, y: -chord.y))
    case nil: return nil
    }
  }
}
