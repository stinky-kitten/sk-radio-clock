//
//  CircleBenchmark.swift
//  sk-radio-clock
//
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

#if SWIFT_PACKAGE
  @testable import RadioClockLogic
#endif

enum CircleBenchmark: Int {
  case baseline, binary, analytical, refinedChord, singleChord, tangent

  var label: StaticString {
    switch self {
    case .baseline: "BASELINE"
    case .binary: "BINARY"
    case .analytical: "ANALYTICAL"
    case .refinedChord: "REFINED_CHORD"
    case .singleChord: "SINGLE_CHORD"
    case .tangent: "TANGENT"
    }
  }

  static let workloadCount: UInt64 = 6
  static let radii: InlineArray<6, Int> = [4, 12, 24, 32, 40, 47]
  static let combinationCount = workloadCount * UInt64(radii.count)
  static let positionCount: UInt64 = 16
  static let samplesPerCombination: UInt64 = 64
  static let warmupRequests = combinationCount * positionCount
  static let measuredRequests = combinationCount * samplesPerCombination
  static let size = PixelSize(width: 64, height: 64)

  struct Sample {
    let index: Int
    let workload: CircleBenchmark
    let radius: Int
    let position: Int

    var centre: DrawingPoint { CircleBenchmark.centre(at: position) }
    var geometryIndex: Int { index / Int(workloadCount) * Int(positionCount) + position }
  }

  struct Geometry {
    var partial: UInt64 = 0
    var full: UInt64 = 0
  }

  struct Result {
    private var profile = RenderProfile()
    private(set) var overruns: UInt64 = 0
    private(set) var fallbacks: UInt64 = 0
    private(set) var onTimeFallbacks: UInt64 = 0
    private(set) var onTimeBoundaryPixels: UInt64 = 0
    private(set) var onTimeMinUs: UInt64 = 0
    private(set) var onTimeMaxUs: UInt64 = 0
    private(set) var onTimeTotalUs: UInt64 = 0

    var statistics: RenderProfile.Statistics { profile.statistics }
    var onTimeCount: UInt64 { statistics.completed - statistics.completedLate }
    var onTimeMeanUs: UInt64 { onTimeCount == 0 ? 0 : onTimeTotalUs / onTimeCount }

    mutating func record(
      startedAt: UInt64, finishedAt: UInt64, deadline: UInt64, completed: Bool,
      fallbacks: UInt64, geometry: Geometry
    ) {
      let firstOnTime = onTimeCount == 0
      profile.recordReceived()
      profile.recordRender(startedAt: startedAt, finishedAt: finishedAt, deadline: deadline, completed: completed)
      self.fallbacks += fallbacks
      if finishedAt >= deadline { overruns += 1 }
      guard completed, finishedAt < deadline else { return }
      let duration = finishedAt - startedAt
      onTimeFallbacks += fallbacks
      onTimeBoundaryPixels += geometry.partial
      onTimeMinUs = firstOnTime ? duration : min(onTimeMinUs, duration)
      onTimeMaxUs = max(onTimeMaxUs, duration)
      onTimeTotalUs += duration
    }
  }

  static func progressPercent(after measured: UInt64) -> UInt64? {
    let quarter = measuredRequests / 4
    guard measured > 0, measured <= measuredRequests, measured % quarter == 0 else { return nil }
    return measured / quarter * 25
  }

  // All combinations see each position before advancing. Rotate the entire
  // order by one slot per position group, including across repeat boundaries.
  static func sample(_ request: UInt64) -> Sample {
    let group = request / combinationCount
    let slot = Int((request % combinationCount + group % combinationCount) % combinationCount)
    let radiusIndex = slot % radii.count
    let workloadIndex = slot / radii.count
    return Sample(
      index: radiusIndex * Int(workloadCount) + workloadIndex, workload: Self(rawValue: workloadIndex)!,
      radius: radii[radiusIndex], position: Int(group % positionCount))
  }

  static func centre(at position: Int) -> DrawingPoint {
    let offsets = FiveWayCircleComparison.quarterOffsets(for: position)
    return DrawingPoint(x: 32 + Float(offsets.x) * 0.25, y: 32 + Float(offsets.y) * 0.25)
  }

  // Geometric cell classification before quantisation, independent of how a
  // workload paints. These quarter-pixel distances and squares are exact.
  static func geometry(at centre: DrawingPoint, radius: Float) -> Geometry {
    let squaredRadius = radius * radius
    var result = Geometry()
    for y in 0..<size.height {
      let dy = abs(Float(y) + 0.5 - centre.y)
      let nearY = max(0, dy - 0.5)
      let farY = dy + 0.5
      for x in 0..<size.width {
        let dx = abs(Float(x) + 0.5 - centre.x)
        let nearX = max(0, dx - 0.5)
        let farX = dx + 0.5
        if farX * farX + farY * farY <= squaredRadius {
          result.full += 1
        } else if nearX * nearX + nearY * nearY < squaredRadius {
          result.partial += 1
        }
      }
    }
    return result
  }

  func paint(
    into context: inout DrawingContext, centre: DrawingPoint, radius: Float, fallbacks: inout UInt64
  ) -> Bool {
    guard context.contextSize == Self.size else { return false }
    context.fillColor = .black
    guard context.fillRect(context.contextFrame) else { return false }
    guard self != .baseline else { return true }

    context.fillColor = .blue
    if self == .binary {
      return context.fillCircle(centre: DrawingPoint(x: centre.x - 0.5, y: centre.y - 0.5), radius: radius)
    }

    var row: InlineArray<64, UInt8> = .init(repeating: 0)
    var scratch = row.mutableSpan
    if self == .refinedChord {
      return context.fillRefinedChordCircle(centre: centre, radius: radius, coverageRow: &scratch)
    }

    let top = max(0, Int((centre.y - radius).rounded(.down)))
    let bottom = min(Self.size.height, Int((centre.y + radius).rounded(.up)))
    let squaredRadius = radius * radius
    let color = context.fillColor
    for y in top..<bottom {
      guard let (visible, interior) = Self.scanline(y: y, centre: centre, squaredRadius: squaredRadius) else {
        continue
      }
      if visible == interior {
        guard context.writeOpaqueSpan(y: y, from: interior.lowerBound, to: interior.upperBound, color: color)
        else { return false }
        continue
      }

      let edges: InlineArray<2, Range<Int>> = [
        visible.lowerBound..<interior.lowerBound, interior.upperBound..<visible.upperBound,
      ]
      for edge in edges {
        for x in edge {
          let pixel = PixelPoint(x: x, y: y)
          let coverage: Float
          if self == .analytical {
            coverage = analyticalDiskCoverage(at: pixel, centre: centre, radius: radius)
          } else if let linear = FiveWayCircleComparison.linearCoverage(
            at: pixel, centre: centre, radius: radius, tangent: self == .tangent)
          {
            coverage = linear
          } else {
            fallbacks += 1
            coverage = analyticalDiskCoverage(at: pixel, centre: centre, radius: radius)
          }
          scratch[x] = coverage.unitQuantized8
        }
      }

      // The opaque span takes the row checkpoint. If it is empty, take the
      // checkpoint explicitly. Edge writes consult sticky status only.
      if interior.isEmpty {
        guard context.checkDeadline() else { return false }
      } else {
        guard context.writeOpaqueSpan(y: y, from: interior.lowerBound, to: interior.upperBound, color: color)
        else { return false }
      }
      for edge in edges {
        for x in edge {
          let alpha = scratch[x]
          guard alpha > 0 else { continue }
          guard context.blendPixel(at: PixelPoint(x: x, y: y), to: color, withAlpha: alpha) else {
            return false
          }
        }
      }
    }
    return true
  }

  // The widest chord includes cells with positive area. The narrowest
  // chord includes only whole cells. Integer radii and quarter-pixel
  // centres keep the squared distances exact over the benchmark grid.
  static func scanline(y: Int, centre: DrawingPoint, squaredRadius: Float) -> (Range<Int>, Range<Int>)? {
    let top = Float(y) - centre.y
    let bottom = top + 1
    let near = max(top, -bottom, 0)
    let outerSquared = squaredRadius - near * near
    guard outerSquared > 0 else { return nil }
    let outer = outerSquared.squareRoot()
    let left = max(0, Int((centre.x - outer).rounded(.down)))
    let right = min(size.width, Int((centre.x + outer).rounded(.up)))
    guard left < right else { return nil }

    let far = max(abs(top), abs(bottom))
    let inner = max(0, squaredRadius - far * far).squareRoot()
    let firstFull = min(right, max(left, Int((centre.x - inner).rounded(.up))))
    let endFull = max(firstFull, min(right, Int((centre.x + inner).rounded(.down))))
    return (left..<right, firstFull..<endFull)
  }
}
