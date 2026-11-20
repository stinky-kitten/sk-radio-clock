#if SWIFT_PACKAGE
  @testable import RadioClockLogic
#endif

struct StationaryCircleComparison {
  private static let radii: InlineArray<3, Int> = [12, 24, 32]
  private static let positions: InlineArray<4, Int> = [0, 5, 10, 13]
  private static let algorithms: InlineArray<4, CircleBenchmark> = [.analytical, .refinedChord, .singleChord, .tangent]
  static let count = radii.count * positions.count * algorithms.count
  static let holdUs: UInt64 = 3_000_000

  let index: Int

  init(elapsedUs: UInt64) {
    index = Int(elapsedUs / Self.holdUs % UInt64(Self.count))
  }

  var workload: CircleBenchmark { Self.algorithms[index % Self.algorithms.count] }
  var radius: Int { Self.radii[index / (Self.positions.count * Self.algorithms.count)] }
  private var position: Int { Self.positions[index / Self.algorithms.count % Self.positions.count] }
  var offsets: (x: Int, y: Int) { FiveWayCircleComparison.quarterOffsets(for: position) }
  var centre: DrawingPoint { CircleBenchmark.centre(at: position) }

  func paint(into context: inout DrawingContext) -> Bool {
    var fallbacks: UInt64 = 0
    return workload.paint(into: &context, centre: centre, radius: Float(radius), fallbacks: &fallbacks)
  }
}
