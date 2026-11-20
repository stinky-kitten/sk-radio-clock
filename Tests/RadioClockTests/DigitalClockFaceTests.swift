import Testing

@testable import RadioClockLogic

private struct DigitalClockFaceTests {
  @Test(
    "All twelve numeric months render the centred DD.MM.YYYY date without changing seconds progress",
    arguments: [
      (1, "02.01.2026"), (2, "02.02.2026"), (3, "02.03.2026"), (4, "02.04.2026"),
      (5, "02.05.2026"), (6, "02.06.2026"), (7, "02.07.2026"), (8, "02.08.2026"),
      (9, "02.09.2026"), (10, "02.10.2026"), (11, "02.11.2026"), (12, "02.12.2026"),
    ] as [(Int, StaticString)])
  func monthRendering(_ month: Int, _ date: StaticString) {
    let result = render(snapshot(month: month))
    #expect(result.completed)
    // At 37 seconds, 150 of the 244 perimeter pixels are complete. The
    // next pixel has brightness 153/255; purple's channels scale to 76.
    #expect(result.pixels[62 * 64 + 35] == 0xff80_0080)
    #expect(result.pixels[62 * 64 + 34] == 0xff4c_004c)
    #expect(result.pixels[62 * 64 + 33] == 0xff20_0020)
    expectLabel(result.pixels, date, x: 4, baseline: 56, rows: 48..<57)
  }

  @Test("The 64x64 layout places time above right-aligned seconds, weekday and numeric date")
  func layout() {
    let layout = DigitalClockFace.LayoutMetrics(size: PixelSize(width: 64, height: 64))
    #expect(layout.indicatorFrame == PixelRect(x: 57, y: 3, width: 4, height: 4))
    #expect(layout.timeFrame == PixelRect(x: 3, y: 4, width: 58, height: 25))
    #expect(layout.secondsFrame == PixelRect(x: 4, y: 25, width: 56, height: 9))
    #expect(layout.dayOfWeekFrame == PixelRect(x: 4, y: 36, width: 56, height: 9))
    #expect(layout.dateFrame == PixelRect(x: 4, y: 48, width: 56, height: 9))
    #expect(layout.timeBaseline == 24 && layout.secondsBaseline == 33)
    #expect(layout.dayOfWeekBaseline == 44 && layout.dateBaseline == 56)
  }

  @Test(
    "The composed time and changing seconds use independently fixed pens and baselines",
    arguments: [(0, "00"), (9, "09"), (10, "10"), (37, "37"), (59, "59")] as [(Int, StaticString)])
  func timeAndSecondsPlacement(_ second: Int, _ label: StaticString) throws {
    let result = render(snapshot(second: second))
    try expectTime1742(result.pixels)
    // The two six-pixel advances start at x=47 and end at x=59, one pixel inside the frame.
    expectLabel(result.pixels, label, x: 47, baseline: 33, rows: 25..<34)
  }

  private func expectTime1742(_ pixels: [UInt32]) throws {
    var reference = Array(repeating: UInt32(0xff00_0000), count: 4096)
    try reference.withUnsafeMutableBufferPointer { buffer in
      var context = DrawingContext(
        framebuffer: buffer, contextSize: PixelSize(width: 64, height: 64), pixelFormat: .bgrx8888)!
      // 17:42 advances 55 pixels. The literal pens use the font's independently
      // tested advances, without calling clock-face formatting or layout code.
      for (code, x) in [(0x31, 4), (0x37, 16), (0xa789, 28), (0x34, 35), (0x32, 47)] {
        let scalar = try #require(Unicode.Scalar(code))
        let glyph = try #require(ClockFont.glyph(for: scalar))
        context.drawGlyph(
          glyph, atPen: PixelPoint(x: x, y: 24),
          color: code == 0xa789 ? .gray : .purple)
      }
    }
    for y in 8..<25 {
      let timeColumns = (y * 64 + 3)..<(y * 64 + 61)
      #expect(Array(pixels[timeColumns]) == Array(reference[timeColumns]))
    }
  }

  @Test(
    "Every weekday is centred between seconds and date; missing or unknown weekdays show a question mark",
    arguments: [
      (0, false, "Sunday", 14), (1, false, "Monday", 13), (2, false, "Tuesday", 11),
      (3, false, "Wednesday", 4), (4, false, "Thursday", 8), (5, false, "Friday", 15),
      (6, false, "Saturday", 8), (nil, false, "?", 29), (1, true, "?", 29),
    ] as [(Int?, Bool, StaticString, Int)])
  func weekdayPlacement(_ weekday: Int?, _ unknown: Bool, _ text: StaticString, _ x: Int) {
    let result = render(
      snapshot(weekday: weekday, weekdayState: unknown ? .unknown : .supported),
      expectedReads: 86 + text.utf8CodeUnitCount)
    expectLabel(
      result.pixels, text, x: x, baseline: 44, rows: 36..<45,
      color: unknown || weekday == nil ? .red : .purple)
  }

  @Test("Unknown date and time show placeholders and a dim perimeter without elapsed progress")
  func unknownRendering() {
    let result = render(.unknown, expectedReads: 87)
    #expect(result.completed)
    #expect(perimeter.allSatisfy { result.pixels[$0] == 0xff40_0000 })
    #expect(result.pixels.contains { $0 == PixelColor32.red.xrgb8888 })
    expectLabel(result.pixels, "??", x: 47, baseline: 33, rows: 25..<34, color: .red)
    expectLabel(result.pixels, "?", x: 29, baseline: 44, rows: 36..<45, color: .red)
    expectLabel(result.pixels, "??.??.????", x: 4, baseline: 56, rows: 48..<57, color: .red)
  }

  @Test(
    "The dim perimeter remains when second timing or the calendar second is unavailable",
    arguments: [(37, false), (nil, true), (nil, false)] as [(Int?, Bool)])
  func unavailableSeconds(_ second: Int?, _ timing: Bool) {
    let result = render(snapshot(second: second, microseconds: 999_999, hasTiming: timing))
    #expect(perimeter.allSatisfy { result.pixels[$0] == 0xff40_0000 })
    expectLabel(result.pixels, "??", x: 47, baseline: 33, rows: 25..<34, color: .red)
    #expect((0..<64).allSatisfy { result.pixels[$0] == 0xff00_0000 && result.pixels[63 * 64 + $0] == 0xff00_0000 })
    #expect((0..<64).allSatisfy { result.pixels[$0 * 64] == 0xff00_0000 && result.pixels[$0 * 64 + 63] == 0xff00_0000 })
  }

  @Test(
    "Clockwise perimeter progress completes pixels at full brightness and fades the leading pixel from dim to full",
    arguments: [
      (0, 0, 0, 0xff20_0020), (0, 125_000, 0, 0xff50_0050),
      (0, 245_901, 0, 0xff7f_007f), (0, 250_000, 1, 0xff21_0021),
      (0, 500_000, 2, 0xff23_0023), (15, 0, 61, 0xff20_0020),
      (30, 0, 122, 0xff20_0020), (45, 0, 183, 0xff20_0020),
      (59, 999_999, 243, 0xff7f_007f), (59, UInt32.max, 243, 0xff7f_007f),
    ] as [(Int, UInt32, Int, UInt32)])
  func secondsProgress(_ second: Int, _ microseconds: UInt32, _ completed: Int, _ leading: UInt32) {
    let result = render(snapshot(second: second, microseconds: microseconds))
    // Four literal, non-overlapping edges include all corners exactly once.
    // Fraction fixtures above are calculated for 244 pixels over 60 seconds.
    #expect(perimeter.count == 244 && Set(perimeter).count == 244)
    #expect(
      perimeter.enumerated().allSatisfy { index, offset in
        result.pixels[offset] == (index < completed ? 0xff80_0080 : (index == completed ? leading : 0xff20_0020))
      })
  }

  @Test("The perimeter resets at a minute boundary and replaces stale progress in a reused framebuffer")
  func minuteBoundary() {
    let before = render(snapshot(second: 59, microseconds: 999_999))
    let next = render(snapshot(minute: 43, second: 0), initial: before.pixels)
    let fresh = render(snapshot(minute: 43, second: 0))
    #expect(next.pixels == fresh.pixels)
    #expect(perimeter.allSatisfy { next.pixels[$0] == 0xff20_0020 })
    // The time's 3 can reach row 24. The seconds frame starts on row 25.
    expectLabel(next.pixels, "00", x: 47, baseline: 33, rows: 25..<34)
    let unavailable = render(snapshot(hasTiming: false), initial: before.pixels)
    #expect(perimeter.allSatisfy { unavailable.pixels[$0] == 0xff40_0000 })
  }

  @Test(
    "Expired deadlines cancel before each component operation and preserve exactly the preceding writes",
    arguments: [0, 64, 68, 70, 71, 76, 82], [100, 101] as [UInt64])
  func cancellation(_ completedOperations: Int, _ expiredAt: UInt64) {
    let result = render(snapshot(), times: Array(repeating: 1, count: completedOperations) + [expiredAt, 102])
    #expect(!result.completed && result.status == .deadlineExceeded)
    #expect(result.reads == completedOperations + 1)
    let full = render(snapshot()).pixels
    let outline = Set(perimeter)
    #expect(
      result.pixels.enumerated().allSatisfy { index, pixel in
        if completedOperations == 0 { return pixel == 0x1234_5678 }
        let x = index % 64
        let y = index / 64
        // The fixed 17:42 raster ends by row 24. The seconds frame starts at 25.
        let written =
          (completedOperations >= 68 && (57..<61).contains(x) && (3..<7).contains(y))
          || (completedOperations >= 70 && (4..<60).contains(x) && (25..<34).contains(y))
          || (completedOperations >= 71 && outline.contains(index))
          || (completedOperations >= 76 && (4..<60).contains(x) && (8..<25).contains(y))
          || (completedOperations >= 82 && (4..<60).contains(x) && (36..<45).contains(y))
        return pixel == (written ? full[index] : 0xff00_0000)
      })
  }

  @Test("The final date glyph completes without a post-render deadline check")
  func finalOperation() {
    let result = render(snapshot(), times: Array(repeating: 1, count: 92) + [100])
    #expect(result.completed && result.status == .active && result.reads == 92)
    expectLabel(result.pixels, "02.09.2026", x: 4, baseline: 56, rows: 48..<57)
    let cancelled = render(snapshot(), times: Array(repeating: 1, count: 91) + [100])
    #expect(!cancelled.completed && cancelled.status == .deadlineExceeded && cancelled.reads == 92)
    expectLabel(cancelled.pixels, "02.09.202", x: 4, baseline: 56, rows: 48..<57)
  }

  @Test("The radio indicator is inset three pixels from the top and right and is omitted for NTP")
  func ntpIndicator() {
    let msf = render(snapshot())
    let ntp = render(snapshot(), source: .ntp)
    #expect(msf.pixels[3 * 64 + 57] == PixelColor32.green.xrgb8888)
    #expect(ntp.pixels[3 * 64 + 57] == PixelColor32.black.xrgb8888)
    #expect(msf.reads == 92 && ntp.reads == 88)
    #expect(
      msf.pixels.enumerated().allSatisfy { index, pixel in
        let indicator = (57..<61).contains(index % 64) && (3..<7).contains(index / 64)
        return indicator ? pixel == 0xff00_ff00 && ntp.pixels[index] == 0xff00_0000 : pixel == ntp.pixels[index]
      })
  }

  // Clockwise traversal: top, right, bottom, left. Each edge owns its starting
  // corner and excludes its ending corner. No production geometry is used.
  private var perimeter: [Int] {
    (1..<62).map { 64 + $0 } + (1..<62).map { $0 * 64 + 62 }
      + (2...62).reversed().map { 62 * 64 + $0 } + (2...62).reversed().map { $0 * 64 + 1 }
  }

  private func snapshot(
    month: Int = 9, minute: Int = 42, second: Int? = 37, microseconds: UInt32 = 0, hasTiming: Bool = true,
    weekday: Int? = 1, weekdayState: EpistemicState = .supported
  ) -> ClockSnapshot {
    ClockSnapshot(
      calendarDateTime: CalendarDateTimeComponents(
        year: 2026, month: month, dayOfMonth: 2, dayOfWeek: weekday,
        hour: 17, minute: minute, second: second, timeZone: .gmt),
      clockState: ClockState(
        year: .supported, month: .supported, dayOfMonth: .supported,
        dayOfWeek: weekdayState, hour: .supported, minute: .supported, timeZone: .supported),
      subsecondMicroseconds: microseconds, hasSecondTiming: hasTiming)
  }

  // Font rasterisation is tested separately. Here literal labels, pen positions
  // and baselines are the composition oracle, independent of face formatting.
  private func expectLabel(
    _ pixels: [UInt32], _ text: StaticString, x: Int, baseline: Int, rows: Range<Int>, color: PixelColor32 = .purple
  ) {
    var reference = Array(repeating: UInt32(0xff00_0000), count: 4096)
    reference.withUnsafeMutableBufferPointer { buffer in
      var context = DrawingContext(
        framebuffer: buffer, contextSize: PixelSize(width: 64, height: 64), pixelFormat: .bgrx8888)!
      context.drawString(
        text, font: PixelOperator8Font.self, atPen: PixelPoint(x: x, y: baseline), color: color,
        clippedTo: PixelRect(x: 4, y: rows.lowerBound, width: 56, height: rows.count))
    }
    for y in rows {
      #expect(Array(pixels[(y * 64 + 4)..<(y * 64 + 60)]) == Array(reference[(y * 64 + 4)..<(y * 64 + 60)]))
      for x in [0, 2, 3, 60, 61, 63] { #expect(pixels[y * 64 + x] == 0xff00_0000) }
    }
  }

  private func render(
    _ snapshot: ClockSnapshot, times: [UInt64]? = nil, source: TimeSource = .msf,
    expectedReads: Int = 92, initial: [UInt32]? = nil
  ) -> (completed: Bool, pixels: [UInt32], status: DrawingContext.Status, reads: Int) {
    let face = DigitalClockFace(
      size: PixelSize(width: 64, height: 64),
      configuration: ClockConfiguration(timeSource: source, theme: .standard, timeZone: .uk))
    let display = MSFDisplaySnapshot(
      clockSnapshot: snapshot, secondPhaseBin: nil, timestamp: 0,
      signalHigh: true, highBins: 0, lowBins: 0)
    var pixels = initial ?? Array(repeating: UInt32(0x1234_5678), count: 64 * 64)
    var status = DrawingContext.Status.active
    var reads = 0
    // 64 clear rows + 4 MSF indicator rows + 2 seconds glyphs + 1 perimeter
    // operation + 5 time glyphs + 6 Monday glyphs + 10 numeric-date glyphs.
    let count = expectedReads - (source == .ntp ? 4 : 0)
    let completed = RenderHostTime.withTimestamps(times ?? Array(repeating: 1, count: count)) {
      let completed = pixels.withUnsafeMutableBufferPointer {
        var context = DrawingContext(
          framebuffer: $0, contextSize: PixelSize(width: 64, height: 64), pixelFormat: .bgrx8888,
          renderDeadline: RenderDeadline(timeUs: 100))!
        let completed = face.render(into: &context, displaySnapshot: display)
        status = context.status
        return completed && context.canContinue
      }
      reads = RenderHostTime.readCount
      return completed
    }
    if times == nil {
      #expect(completed && status == .active)
      #expect(reads == count)
    }
    return (completed, pixels, status, reads)
  }

  @Test("Acquired time, date and weekday retain their normal colours when radio evidence is unknown")
  func acquiredUnknownEvidence() throws {
    let known = snapshot()

    let held = ClockSnapshot(
      calendarDateTime: known.calendarDateTime,
      clockState: .unknown,
      subsecondMicroseconds: known.subsecondMicroseconds,
      hasSecondTiming: known.hasSecondTiming,
      hasAcquiredTime: true
    )

    let expected = render(known)
    let actual = render(held)

    #expect(actual.pixels == expected.pixels)
    try expectTime1742(actual.pixels)
    expectLabel(actual.pixels, "Monday", x: 13, baseline: 44, rows: 36..<45)
    expectLabel(actual.pixels, "02.09.2026", x: 4, baseline: 56, rows: 48..<57)
  }

  @Test("Acquisition and confirmed evidence cannot supply missing calendar values")
  func acquiredMissingCalendar() throws {
    let held = ClockSnapshot(
      calendarDateTime: CalendarDateTimeComponents(
        year: nil, month: nil, dayOfMonth: nil, dayOfWeek: nil,
        hour: 17, minute: 42, second: 37, timeZone: .gmt),
      clockState: ClockState(
        year: .confirmed, month: .confirmed, dayOfMonth: .confirmed, dayOfWeek: .confirmed,
        hour: .unknown, minute: .unknown, timeZone: .unknown),
      hasSecondTiming: true,
      hasAcquiredTime: true)

    let result = render(held, expectedReads: 87)
    try expectTime1742(result.pixels)
    expectLabel(result.pixels, "?", x: 29, baseline: 44, rows: 36..<45, color: .red)
    expectLabel(result.pixels, "??.??.????", x: 4, baseline: 56, rows: 48..<57, color: .red)
  }
}
