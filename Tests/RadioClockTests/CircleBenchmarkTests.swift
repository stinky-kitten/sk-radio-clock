import Testing

@testable import RadioClockLogic

@Test("Circle benchmark balances every workload across positions and order slots")
func circleBenchmarkSchedule() {
  let warmup = CircleBenchmark.warmupRequests
  #expect(warmup == 576)
  #expect(CircleBenchmark.measuredRequests == 2_304)
  #expect(CircleBenchmark.samplesPerCombination == 64)
  #expect(warmup + CircleBenchmark.measuredRequests == 2_880)
  let radii = [4, 12, 24, 32, 40, 47]
  var warmupVisits = Array(repeating: 0, count: 36 * 16)
  var measuredVisits = warmupVisits
  var orderSlots = Array(repeating: 0, count: 36 * 36)
  for request in 0..<(warmup + CircleBenchmark.measuredRequests) {
    let sample = CircleBenchmark.sample(request)
    let position = Int(request / 36 % 16)
    #expect(sample.position == position)
    #expect(sample.centre == DrawingPoint(x: 32 + Float(position % 4) / 4, y: 32 + Float(position / 4) / 4))
    #expect(sample.radius == radii[sample.index / 6])
    #expect(sample.workload.rawValue == sample.index % 6)
    #expect(sample.geometryIndex == sample.index / 6 * 16 + position)
    let key = sample.index * 16 + position
    if request < warmup {
      warmupVisits[key] += 1
    } else {
      measuredVisits[key] += 1
      orderSlots[sample.index * 36 + Int(request % 36)] += 1
    }
  }
  #expect(warmupVisits.allSatisfy { $0 == 1 })
  #expect(measuredVisits.allSatisfy { $0 == 4 })
  #expect(orderSlots.allSatisfy { (1...2).contains($0) })
}

@Test("Circle benchmark progress fires only at measured-request quarter boundaries")
func circleBenchmarkProgress() {
  let reports = (0...2_305).compactMap { count in
    CircleBenchmark.progressPercent(after: UInt64(count)).map { [UInt64(count), $0] }
  }
  #expect(reports == [[576, 25], [1_152, 50], [1_728, 75], [2_304, 100]])
}

@Test(
  "Benchmark scanlines match the previous per-cell coverage and fallback counts",
  arguments: [4, 12, 24, 32, 40, 47])
func circleBenchmarkFramebuffers(_ radius: Int) throws {
  var distinctions = Set<Int>()
  let black: UInt32 = 0xff00_0000
  for position in 0..<16 {
    let centre = CircleBenchmark.centre(at: position)
    for index in 0..<6 {
      let workload = try #require(CircleBenchmark(rawValue: index))
      if radius != 4, workload == .baseline || workload == .binary || workload == .refinedChord { continue }
      var pixels = Array(repeating: UInt32(0x1234_5678), count: 4096)
      var fallbacks: UInt64 = 0
      try pixels.withUnsafeMutableBufferPointer { buffer in
        var context = try #require(
          DrawingContext(framebuffer: buffer, contextSize: CircleBenchmark.size, pixelFormat: .bgrx8888))
        let completed = workload.paint(into: &context, centre: centre, radius: Float(radius), fallbacks: &fallbacks)
        #expect(completed)
      }
      var expectedFallbacks: UInt64 = 0
      for y in 0..<64 {
        for x in 0..<64 {
          let pixel = PixelPoint(x: x, y: y)
          let exact = analyticalDiskCoverage(at: pixel, centre: centre, radius: Float(radius))
          let expected: Float
          switch workload {
          case .baseline: expected = 0
          case .binary:
            let dx = Float(x) + 0.5 - centre.x
            let dy = Float(y) + 0.5 - centre.y
            expected = dx * dx + dy * dy <= 16 ? 1 : 0
          case .analytical: expected = exact
          case .refinedChord: expected = diskCoverage(at: pixel, centre: centre, radius: 4)
          case .singleChord, .tangent:
            if let linear = FiveWayCircleComparison.linearCoverage(
              at: pixel, centre: centre, radius: Float(radius), tangent: workload == .tangent)
            {
              expected = linear
            } else {
              expectedFallbacks += 1
              expected = exact
            }
          }
          let byte = expected.unitQuantized8
          if byte != exact.unitQuantized8 { distinctions.insert(index) }
          #expect(pixels[y * 64 + x] == black | UInt32(byte))
        }
      }
      #expect(fallbacks == expectedFallbacks)
    }
  }
  if radius == 4 {
    #expect(distinctions == [0, 1, 3, 4, 5])
  }
}

@Test("Circle benchmark geometry counts only visible cells and radius 47 fully covers the panel")
func circleBenchmarkGeometry() {
  for radius in CircleBenchmark.radii {
    for position in 0..<16 {
      let centre = CircleBenchmark.centre(at: position)
      let counts = CircleBenchmark.geometry(at: centre, radius: Float(radius))
      var expected = CircleBenchmark.Geometry()
      var boundaryCandidates = 0
      var opaqueRows = 0
      for y in 0..<64 {
        let scanline = CircleBenchmark.scanline(y: y, centre: centre, squaredRadius: Float(radius * radius))
        if let (visible, interior) = scanline {
          boundaryCandidates += visible.count - interior.count
          if visible == interior { opaqueRows += 1 }
          #expect(visible.lowerBound >= 0 && visible.upperBound <= 64)
        }
        for x in 0..<64 {
          let area = analyticalDiskCoverage(at: PixelPoint(x: x, y: y), centre: centre, radius: Float(radius))
          #expect((scanline?.0.contains(x) ?? false) == (area > 0))
          #expect((scanline?.1.contains(x) ?? false) == (area == 1))
          if area == 1 {
            expected.full += 1
          } else if area > 0 {
            expected.partial += 1
          }
        }
      }
      #expect(counts.full == expected.full && counts.partial == expected.partial)
      #expect(boundaryCandidates == Int(counts.partial))
      if radius == 47 {
        #expect(counts.full == 4096 && counts.partial == 0)
        #expect(opaqueRows == 64 && boundaryCandidates == 0)
      }
    }
  }
}

@Test("Larger benchmark circles paint clipped pixels safely in all workloads", arguments: [12, 24, 32, 40, 47])
func circleBenchmarkLargerFramebuffers(_ radius: Int) throws {
  let centre = CircleBenchmark.centre(at: 15)
  let black: UInt32 = 0xff00_0000
  let blue: UInt32 = 0xff00_00ff
  for index in 0..<6 {
    let workload = try #require(CircleBenchmark(rawValue: index))
    var pixels = Array(repeating: UInt32(0x1234_5678), count: 4096)
    var fallbacks: UInt64 = 0
    try pixels.withUnsafeMutableBufferPointer { buffer in
      var context = try #require(
        DrawingContext(framebuffer: buffer, contextSize: CircleBenchmark.size, pixelFormat: .bgrx8888))
      #expect(workload.paint(into: &context, centre: centre, radius: Float(radius), fallbacks: &fallbacks))
    }
    if workload == .baseline {
      #expect(pixels.allSatisfy { $0 == black })
      continue
    }
    #expect(pixels[32 * 64 + 32] == blue)
    if radius == 47 {
      #expect(pixels.allSatisfy { $0 == blue })
      #expect(fallbacks == 0)
    } else {
      #expect(pixels[0] == black)
    }
    if workload == .analytical {
      for y in 0..<64 {
        for x in 0..<64 {
          let area = analyticalDiskCoverage(at: PixelPoint(x: x, y: y), centre: centre, radius: Float(radius))
          #expect(pixels[y * 64 + x] == black | UInt32(area.unitQuantized8))
        }
      }
    }
  }
}

@Test("Benchmark timing isolates combinations and excludes rejected and late renders from comparisons")
func circleBenchmarkResults() {
  var results = Array(repeating: CircleBenchmark.Result(), count: 36)
  let geometry = CircleBenchmark.Geometry(partial: 100, full: 50)
  results[0].record(startedAt: 10, finishedAt: 20, deadline: 50, completed: true, fallbacks: 0, geometry: geometry)
  results[1].record(startedAt: 10, finishedAt: 50, deadline: 50, completed: false, fallbacks: 2, geometry: geometry)
  #expect(results[1].onTimeCount == 0 && results[1].onTimeMeanUs == 0)
  results[1].record(startedAt: 50, finishedAt: 51, deadline: 50, completed: false, fallbacks: 0, geometry: geometry)
  results[1].record(startedAt: 10, finishedAt: 60, deadline: 50, completed: true, fallbacks: 4, geometry: geometry)
  results[1].record(startedAt: 10, finishedAt: 30, deadline: 50, completed: true, fallbacks: 3, geometry: geometry)
  results[1].record(startedAt: 10, finishedAt: 40, deadline: 50, completed: true, fallbacks: 5, geometry: geometry)
  #expect(results[0].onTimeTotalUs == 10)
  #expect(results[2].statistics.received == 0)
  let result = results[1]
  #expect(result.statistics.received == 5 && result.statistics.completed == 3 && result.statistics.rejected == 2)
  #expect(result.overruns == 3 && result.statistics.lateStarts == 1 && result.statistics.completedLate == 1)
  #expect(result.onTimeCount == 2 && result.onTimeMinUs == 20 && result.onTimeMaxUs == 30)
  #expect(result.onTimeTotalUs == 50 && result.onTimeMeanUs == 25 && result.statistics.durationTotalUs == 141)
  #expect(result.fallbacks == 14 && result.onTimeFallbacks == 8 && result.onTimeBoundaryPixels == 200)
}

@Test(
  "Benchmark cancellation leaves rejected rows untouched after completing edge-only, mixed or opaque rows",
  arguments: [4, 47])
func circleBenchmarkDeadline(_ radius: Int) throws {
  let black: UInt32 = 0xff00_0000
  let centre = CircleBenchmark.centre(at: 15)
  let firstRow = max(0, Int((centre.y - Float(radius)).rounded(.down)))
  let paintedRows = radius == 4 ? 2 : 1
  var pixels = Array(repeating: UInt32.zero, count: 4096)
  try pixels.withUnsafeMutableBufferPointer { buffer in
    var context = try #require(
      DrawingContext(
        framebuffer: buffer, contextSize: CircleBenchmark.size, pixelFormat: .bgrx8888,
        renderDeadline: RenderDeadline(timeUs: 100)))
    var fallbacks: UInt64 = 0
    RenderHostTime.withTimestamps(Array(repeating: 99, count: 64 + paintedRows) + [100]) {
      let completed = CircleBenchmark.analytical.paint(
        into: &context, centre: centre, radius: Float(radius), fallbacks: &fallbacks)
      #expect(!completed)
      #expect(context.status == .deadlineExceeded)
      #expect(RenderHostTime.readCount == 65 + paintedRows)
    }
    #expect(fallbacks == 0)
  }
  let endRow = firstRow + paintedRows
  for y in firstRow..<endRow {
    for x in 0..<64 {
      let area = analyticalDiskCoverage(at: PixelPoint(x: x, y: y), centre: centre, radius: Float(radius))
      #expect(pixels[y * 64 + x] == black | UInt32(area.unitQuantized8))
    }
  }
  #expect(pixels.prefix(firstRow * 64).allSatisfy { $0 == black })
  #expect(pixels.dropFirst(endRow * 64).allSatisfy { $0 == black })
}
