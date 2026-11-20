//
//  CircleRenderExperiment.swift
//  sk-radio-clock
//
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import SKLSHUB75

@main
struct CircleRenderExperiment {
  static func main() {
    stdio_init_all()
    #if SK_RADIO_CLOCK_CIRCLE_BENCHMARK
      print(
        "CIRCLE_BENCHMARK_START workloads=\(CircleBenchmark.workloadCount) radii=4,12,24,32,40,47 combinations=\(CircleBenchmark.combinationCount) warmup=\(CircleBenchmark.warmupRequests) measured=\(CircleBenchmark.measuredRequests) samples_per_combination=\(CircleBenchmark.samplesPerCombination)"
      )
    #endif
    let panelSize = PixelSize(width: 64, height: 64)
    guard HUB75(panelSize: panelSize).start() else {
      print("CIRCLE_EXPERIMENT HUB75 startup failed")
      return
    }

    #if SK_RADIO_CLOCK_CIRCLE_BENCHMARK
      runBenchmark()
    #elseif SK_RADIO_CLOCK_CIRCLE_STATIONARY_AA
      runStationaryComparison()
    #else
      runDemo()
    #endif
  }

  #if SK_RADIO_CLOCK_CIRCLE_BENCHMARK
    private static func runBenchmark() {
      let renderer = Renderer(clockFace: BenchmarkWorkload())
      var results = InlineArray<36, CircleBenchmark.Result>(repeating: CircleBenchmark.Result())
      var geometry = InlineArray<96, CircleBenchmark.Geometry>(repeating: CircleBenchmark.Geometry())
      var singleChordFallbacks = InlineArray<96, UInt64>(repeating: 0)
      var tangentFallbacks = InlineArray<96, UInt64>(repeating: 0)
      for index in geometry.indices {
        let radius = CircleBenchmark.radii[index / Int(CircleBenchmark.positionCount)]
        let centre = CircleBenchmark.centre(at: index % Int(CircleBenchmark.positionCount))
        geometry[index] = CircleBenchmark.geometry(at: centre, radius: Float(radius))
      }
      var requestIndex: UInt64 = 0
      var lastReport: UInt64 = 0
      let end = CircleBenchmark.warmupRequests + CircleBenchmark.measuredRequests

      while true {
        var request = HUB75RenderRequest()
        guard takeRenderRequest(&request) else { continue }
        let sample = CircleBenchmark.sample(requestIndex)
        let snapshot = MSFDisplaySnapshot(
          clockSnapshot: .unknown, secondPhaseBin: nil, timestamp: requestIndex,
          signalHigh: false, highBins: 0, lowBins: 0)
        BenchmarkWorkload.fallbacks = 0
        let startedAt = time_us_64()
        let completed = renderer.render(&request, displaySnapshot: snapshot)
        let finishedAt = time_us_64()
        if requestIndex >= CircleBenchmark.warmupRequests && requestIndex < end {
          results[sample.index].record(
            startedAt: startedAt, finishedAt: finishedAt, deadline: request.deadline_us, completed: completed,
            fallbacks: BenchmarkWorkload.fallbacks, geometry: geometry[sample.geometryIndex])
          if sample.workload == .singleChord {
            singleChordFallbacks[sample.geometryIndex] += BenchmarkWorkload.fallbacks
          } else if sample.workload == .tangent {
            tangentFallbacks[sample.geometryIndex] += BenchmarkWorkload.fallbacks
          }
          let measured = requestIndex - CircleBenchmark.warmupRequests + 1
          if let percent = CircleBenchmark.progressPercent(after: measured) {
            print(
              "CIRCLE_BENCHMARK_PROGRESS percent=\(percent) measured=\(measured)/\(CircleBenchmark.measuredRequests)")
          }
        }
        requestIndex += 1

        // Repeat the frozen results for serial terminals connected after the run.
        if requestIndex >= end && (lastReport == 0 || finishedAt - lastReport >= 5_000_000) {
          lastReport = finishedAt
          print("CIRCLE_BENCHMARK_DONE")
          for radiusIndex in CircleBenchmark.radii.indices {
            print("CIRCLE_GEOMETRY radius=\(CircleBenchmark.radii[radiusIndex]) partial/full=", terminator: "")
            for position in 0..<Int(CircleBenchmark.positionCount) {
              let counts = geometry[radiusIndex * Int(CircleBenchmark.positionCount) + position]
              if position > 0 { print(",", terminator: "") }
              print("\(counts.partial)/\(counts.full)", terminator: "")
            }
            print("")
            print(
              "CIRCLE_POSITION_FALLBACKS radius=\(CircleBenchmark.radii[radiusIndex]) single_chord/tangent=",
              terminator: "")
            for position in 0..<Int(CircleBenchmark.positionCount) {
              let index = radiusIndex * Int(CircleBenchmark.positionCount) + position
              if position > 0 { print(",", terminator: "") }
              print("\(singleChordFallbacks[index])/\(tangentFallbacks[index])", terminator: "")
            }
            print("")
          }
          print(
            "CIRCLE_COLUMNS radius workload attempted completed rejected overruns late_start late_done on_time mean_us min_us max_us on_time_total_us attempted_total_us fallbacks on_time_fallbacks on_time_boundary_pixels"
          )
          for index in results.indices {
            let result = results[index]
            let statistics = result.statistics
            let radius = CircleBenchmark.radii[index / Int(CircleBenchmark.workloadCount)]
            let workload = CircleBenchmark(rawValue: index % Int(CircleBenchmark.workloadCount))!
            print(
              "CIRCLE_RESULT \(radius) \(workload.label) \(statistics.received) \(statistics.completed) \(statistics.rejected) \(result.overruns) \(statistics.lateStarts) \(statistics.completedLate) \(result.onTimeCount) \(result.onTimeMeanUs) \(result.onTimeMinUs) \(result.onTimeMaxUs) \(result.onTimeTotalUs) \(statistics.durationTotalUs) \(result.fallbacks) \(result.onTimeFallbacks) \(result.onTimeBoundaryPixels)"
            )
          }
          print("CIRCLE_BENCHMARK_END")
        }
      }
    }
  #elseif SK_RADIO_CLOCK_CIRCLE_STATIONARY_AA
    private static func runStationaryComparison() {
      let renderer = Renderer(clockFace: StationaryComparisonWorkload())
      let start = time_us_64()
      var lastIndex: Int?
      while true {
        var request = HUB75RenderRequest()
        guard takeRenderRequest(&request) else { continue }
        let elapsed = time_us_64() - start
        let snapshot = MSFDisplaySnapshot(
          clockSnapshot: .unknown, secondPhaseBin: nil, timestamp: elapsed,
          signalHigh: false, highBins: 0, lowBins: 0)
        if renderer.render(&request, displaySnapshot: snapshot) {
          let frame = StationaryCircleComparison(elapsedUs: elapsed)
          if frame.index != lastIndex {
            let offsets = frame.offsets
            print(
              "CIRCLE_STATIONARY_AA step=\(frame.index + 1)/\(StationaryCircleComparison.count) algorithm=\(frame.workload.label) radius=\(frame.radius) offset_x=\(offsets.x)/4 offset_y=\(offsets.y)/4"
            )
            lastIndex = frame.index
          }
        }
      }
    }
  #else
    private static func runDemo() {
      let renderer = Renderer(clockFace: CircleWorkload())
      var profile = RenderProfile()
      #if SK_RADIO_CLOCK_CIRCLE_FIVE_WAY
        let experimentStart = time_us_64()
        var lastPosition: Int?
      #elseif !SK_RADIO_CLOCK_CIRCLE_COMPARISON
        var phase: UInt64 = 0
      #endif
      while true {
        var request = HUB75RenderRequest()
        if takeRenderRequest(&request) {
          profile.recordReceived()
          #if SK_RADIO_CLOCK_CIRCLE_FIVE_WAY
            let timestamp = time_us_64() - experimentStart
          #elseif SK_RADIO_CLOCK_CIRCLE_COMPARISON
            let timestamp = time_us_64()
          #else
            let timestamp = phase
            phase = (phase + 1) % 8
          #endif
          let snapshot = MSFDisplaySnapshot(
            clockSnapshot: .unknown, secondPhaseBin: nil, timestamp: timestamp,
            signalHigh: false, highBins: 0, lowBins: 0)

          let startedAt = time_us_64()
          let completed = renderer.render(&request, displaySnapshot: snapshot)
          let finishedAt = time_us_64()
          profile.recordRender(
            startedAt: startedAt, finishedAt: finishedAt, deadline: request.deadline_us, completed: completed)
          #if SK_RADIO_CLOCK_CIRCLE_FIVE_WAY
            let index = FiveWayCircleComparison.positionIndex(at: timestamp)
            if completed, index != lastPosition {
              let offsets = FiveWayCircleComparison.quarterOffsets(for: index)
              print("CIRCLE_POSITION index=\(index) offset_x=\(offsets.x)/4 offset_y=\(offsets.y)/4")
              lastPosition = index
            }
          #endif
        }

        if let statistics = profile.takeReport(at: time_us_64()) {
          print("CIRCLE_EXPERIMENT \(CircleWorkload.label)")
          #if SK_RADIO_CLOCK_CIRCLE_FIVE_WAY
            print("CIRCLE_LAYOUT TOP=ANALYTICAL,REFINED_CHORD,SINGLE_CHORD BOTTOM=TANGENT,BINARY,EMPTY")
            print(
              "CIRCLE_FALLBACKS single_chord=\(CircleWorkload.fallbacks.singleChord) tangent=\(CircleWorkload.fallbacks.tangent)"
            )
          #endif
          printRenderProfile(statistics)
        }
      }
    }
  #endif
}

#if SK_RADIO_CLOCK_CIRCLE_BENCHMARK
  private struct BenchmarkWorkload: ClockFace {
    static var fallbacks: UInt64 = 0

    func render(into context: inout DrawingContext, displaySnapshot: MSFDisplaySnapshot) -> Bool {
      let sample = CircleBenchmark.sample(displaySnapshot.timestamp)
      return sample.workload.paint(
        into: &context, centre: sample.centre, radius: Float(sample.radius), fallbacks: &Self.fallbacks)
    }
  }
#elseif SK_RADIO_CLOCK_CIRCLE_STATIONARY_AA
  private struct StationaryComparisonWorkload: ClockFace {
    func render(into context: inout DrawingContext, displaySnapshot: MSFDisplaySnapshot) -> Bool {
      StationaryCircleComparison(elapsedUs: displaySnapshot.timestamp).paint(into: &context)
    }
  }
#else
  private struct CircleWorkload: ClockFace {
    #if SK_RADIO_CLOCK_CIRCLE_FIVE_WAY
      static let label: StaticString = "FIVE_WAY"
      static var fallbacks = FiveWayCircleComparison.Fallbacks()
    #elseif SK_RADIO_CLOCK_CIRCLE_COMPARISON
      static let label: StaticString = "ANALYTICAL_LEFT CHORD_RIGHT"
    #elseif SK_RADIO_CLOCK_CIRCLE_BINARY
      static let label: StaticString = "BINARY"
    #elseif SK_RADIO_CLOCK_CIRCLE_AA
      static let label: StaticString = "AA"
    #else
      static let label: StaticString = "BASELINE"
    #endif

    private static let centres: InlineArray<8, DrawingPoint> = [
      DrawingPoint(x: 32, y: 32), DrawingPoint(x: 32.5, y: 32.5),
      DrawingPoint(x: 32.125, y: 32.375), DrawingPoint(x: 32.75, y: 32.25),
      DrawingPoint(x: 32.25, y: 32.875), DrawingPoint(x: 32.875, y: 32.625),
      DrawingPoint(x: 32.375, y: 32.75), DrawingPoint(x: 32.625, y: 32.125),
    ]

    func render(into context: inout DrawingContext, displaySnapshot: MSFDisplaySnapshot) -> Bool {
      guard context.contextSize == PixelSize(width: 64, height: 64) else { return false }
      context.fillColor = .black
      guard context.fillRect(context.contextFrame) else { return false }

      #if SK_RADIO_CLOCK_CIRCLE_FIVE_WAY
        context.fillColor = .blue
        return FiveWayCircleComparison.paint(into: &context, at: displaySnapshot.timestamp, fallbacks: &Self.fallbacks)
      #elseif SK_RADIO_CLOCK_CIRCLE_COMPARISON
        context.fillColor = .blue
        return CircleRenderComparison.paint(into: &context, at: displaySnapshot.timestamp)
      #elseif SK_RADIO_CLOCK_CIRCLE_BINARY || SK_RADIO_CLOCK_CIRCLE_AA
        let centre = Self.centres[Int(displaySnapshot.timestamp)]
        context.fillColor = .blue
        #if SK_RADIO_CLOCK_CIRCLE_BINARY
          // Map geometric pixel centres to the binary rasteriser's integer samples.
          let binaryCentre = DrawingPoint(x: centre.x - 0.5, y: centre.y - 0.5)
          return context.fillCircle(centre: binaryCentre, radius: 4)
        #else
          var row: InlineArray<64, UInt8> = .init(repeating: 0)
          var scratch = row.mutableSpan
          return context.fillRefinedChordCircle(centre: centre, radius: 4, coverageRow: &scratch)
        #endif
      #else
        return true
      #endif
    }
  }
#endif
