//
//  AnalyticalClockFaceTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

// Every render establishes its own task-local clock session. This suite can
// run concurrently with itself and with the serialized scanner recorder suite.
private struct AnalyticalClockFaceTests {
  @Test(
    "Render deadline uses an inclusive absolute comparison including UInt64 boundaries",
    arguments: [
      (0, 0, true), (1, 0, false), (100, 99, false), (100, 100, true),
      (100, 101, true), (UInt64.max, UInt64.max - 1, false),
      (UInt64.max, UInt64.max, true),
    ] as [(UInt64, UInt64, Bool)])
  func deadlineComparison(_ deadline: UInt64, _ now: UInt64, _ expired: Bool) {
    #expect(RenderDeadline(timeUs: deadline).hasExpired(at: now) == expired)
  }

  @Test(
    "Full face leaves the entire buffer untouched when the first check is equal or late",
    arguments: [100, 101] as [UInt64])
  func expiredBeforeDrawing(_ now: UInt64) {
    let result = faceRender(faceSnapshot(), times: [now])
    #expect(!result.completed && result.reads == 1)
    #expect(result.pixels.allSatisfy { $0 == faceSentinel })
  }

  @Test(
    "64x64 face cancels before each stage and preserves only preceding stage writes",
    arguments: 0..<7, [100, 101] as [UInt64])
  func cancellationBoundary(_ completedStages: Int, _ expiredAt: UInt64) {
    // Cumulative operation checkpoints: 64 clear rows, 4 indicator rows,
    // trace (7 background rows and 3 complete strokes), bits (8 rows and 21 glyphs),
    // then 5 time glyphs and 10 non-space date glyphs.
    let checkpoints = [0, 64, 68, 78, 107, 112, 122]
    let completedOperations = checkpoints[completedStages]
    let times = Array(repeating: UInt64(10), count: completedOperations) + [expiredAt, 102]
    let result = faceRender(faceSnapshot(), times: times)
    let complete = faceRender(faceSnapshot()).pixels
    #expect(!result.completed)
    #expect(result.reads == completedOperations + 1)
    #expect(
      result.pixels.enumerated().allSatisfy { index, pixel in
        if completedStages == 0 {
          return pixel == faceSentinel
        }

        let componentWritten = faceRegions.prefix(completedStages - 1)
          .contains { $0.contains(index) }

        guard componentWritten else { return pixel == 0xff00_0000 }
        // Later date/zone ink falls within earlier components' clip frames.
        // The complete raster is an exact reference only outside those overlaps;
        // fixed samples below and the layering test check the overlapping rows.
        let laterComponentOverlaps = faceRegions.dropFirst(completedStages - 1)
          .contains { $0.contains(index) }
        return pixel != faceSentinel && (laterComponentOverlaps || pixel == complete[index])
      })
    // Independent ink references identify completed AND cancelled components;
    // the full-frame clear alone must not count as drawing any component.
    let references: [(Int, Int, UInt32)] = [
      (58, 2, 0xff00_ff00), (2, 14, 0xff00_ff00), (4, 18, 0xff00_ff00),
      (9, 27, 0xff80_0080), (3, 50, 0xff80_0080), (47, 59, 0xff80_0080),
    ]
    for (component, reference) in references.enumerated() {
      let (x, y, color) = reference
      let expected = completedStages == 0 ? faceSentinel : (component < completedStages - 1 ? color : 0xff00_0000)
      #expect(result.pixels[y * 64 + x] == expected)
    }
  }

  @Test(
    "Full face completes with strictly future operation-boundary deadline checks",
    arguments: [(1, 0), (100, 99), (UInt64.max, UInt64.max - 1)] as [(UInt64, UInt64)])
  func futureDeadline(_ deadline: UInt64, _ now: UInt64) {
    let result = faceRender(faceSnapshot(), times: Array(repeating: now, count: 125), deadline: deadline)
    #expect(result.completed && result.reads == 125)
    #expect(result.pixels[59 * 64 + 47] == 0xff80_0080)
  }

  @Test("Completion means the clear and all six components ran with no extra deadline check after timezone")
  func finalStageHasNoPostcheck() {
    let result = faceRender(faceSnapshot(), times: Array(repeating: 1, count: 124) + [99, 100])
    #expect(result.completed && result.reads == 125)
    #expect(result.pixels[57 * 64 + 59] == 0xff80_0080)
    // The unconsumed 100 is not a measurement of time spent in that stage.
    // These checks cannot prove the physical ownership deadline was met.
  }

  @Test("Host clock sessions reset their cursor and restore an enclosing session")
  func clockScopeReset() {
    RenderHostTime.withTimestamps([12, 13]) {
      #expect(RenderHostTime.readCount == 0)
      #expect(time_us_64() == 12)
      RenderHostTime.withTimestamps([90]) {
        #expect(RenderHostTime.readCount == 0)
        #expect(time_us_64() == 90)
        #expect(RenderHostTime.readCount == 1)
      }
      #expect(RenderHostTime.readCount == 1)
      #expect(time_us_64() == 13)
      #expect(RenderHostTime.readCount == 2)
    }
    RenderHostTime.withTimestamps([7]) {
      #expect(RenderHostTime.readCount == 0)
      #expect(time_us_64() == 7)
      #expect(RenderHostTime.readCount == 1)
    }
  }

  @Test("Independent concurrent host render clock sessions cannot consume each other's scripts")
  func clockSessionIsolation() async {
    await withTaskGroup(of: Bool.self) { group in
      for seed in UInt64(0)..<32 {
        group.addTask {
          RenderHostTime.withTimestamps([seed, seed + 100]) {
            let first = time_us_64()
            // Each actual render has a nested session with a distinct script
            // and deadline. Both completion and cancellation run concurrently.
            let now = 1_000 + seed * 10
            let cancel = seed.isMultiple(of: 2)
            let times = cancel ? [now, now + 1, now + 2] : Array(repeating: now, count: 125)
            let result = faceRender(faceSnapshot(), times: times, deadline: now + 2)
            let second = time_us_64()
            return first == seed && second == seed + 100 && RenderHostTime.readCount == 2
              && result.completed == !cancel && result.reads == (cancel ? 3 : 125)
              && result.pixels[2 * 64 + 58] == (cancel ? faceSentinel : 0xff00_ff00)
              && result.pixels[14 * 64 + 2] == (cancel ? faceSentinel : 0xff00_ff00)
              && (!cancel || result.pixels.prefix(128).allSatisfy { $0 == 0xff00_0000 })
          }
        }
      }
      for await isolated in group { #expect(isolated) }
    }
  }

  @Test("64x64 composition geometry retains baselines gaps and intentionally overlapping component frames")
  func geometry64x64() {
    let layout = AnalyticalClockFace.LayoutMetrics(size: PixelSize(width: 64, height: 64))
    #expect(layout.indicatorFrame == PixelRect(x: 58, y: 2, width: 4, height: 4))
    #expect(layout.traceFrame == PixelRect(x: 2, y: 8, width: 60, height: 7))
    #expect(layout.bitsFrame == PixelRect(x: 2, y: 15, width: 60, height: 8))
    #expect(layout.clockFrame == PixelRect(x: 0, y: 25, width: 64, height: 22))
    #expect(layout.dateFrame == PixelRect(x: 2, y: 45, width: 60, height: 9))
    #expect(layout.timeZoneFrame == PixelRect(x: 42, y: 55, width: 20, height: 9))
    #expect(layout.clockBaseline == 42 && layout.dateBaseline == 53 && layout.timeZoneBaseline == 63)
    // The date frame overlaps the clock frame, below the clock ink.
    // Row 54 separates the date and timezone frames.
  }

  @Test("64x64 acquired face composes indicator waveform bits clock date and BST with exact reference pixels")
  func acquiredComposition() {
    let result = faceRender(faceSnapshot())
    #expect(result.completed && result.reads == 125)
    expectFaceReferences(
      result.pixels,
      [
        (58, 2, 0xff00_ff00), (61, 5, 0xff00_ff00),
        (2, 14, 0xff00_ff00), (2, 8, 0xff00_0f00),
        (3, 11, 0xff00_ff00), (4, 8, 0xff00_ff00), (5, 8, 0xff00_0f00),
        (4, 18, 0xff00_ff00), (5, 18, 0xff00_0f00),  // marker M
        (14, 18, 0xff00_ff00), (15, 21, 0xff00_0f00),  // unknown ?
        (25, 19, 0xff00_0f00), (24, 19, 0xff00_ff00),  // zero
        (9, 27, 0xff80_0080), (17, 27, 0xff80_0080),  // 17
        (30, 30, 0xff80_8080), (31, 34, 0xff00_0000),  // colon and gap
        (42, 27, 0xff80_0080), (51, 27, 0xff80_0080),  // 42
        (3, 50, 0xff80_0080), (9, 49, 0xff80_0080), (18, 49, 0xff80_0080), (24, 50, 0xff80_0080), (32, 50, 0xff80_0080),
        (35, 49, 0xff80_0080), (44, 50, 0xff80_0080), (50, 49, 0xff80_0080), (56, 50, 0xff80_0080),
        (61, 49, 0xff80_0080),
        (47, 59, 0xff80_0080), (53, 59, 0xff80_0080), (59, 57, 0xff80_0080),
        (0, 25, 0xff00_0000), (2, 43, 0xff00_0000), (42, 63, 0xff00_0000),
      ])
    expectFaceWriteFootprint(result.pixels)
    for y in 23..<25 {
      #expect(result.pixels[(y * 64)..<((y + 1) * 64)].allSatisfy { $0 == 0xff00_0000 })
    }
  }

  @Test(
    "Activity indicator follows raw HIGH and LOW rather than inventing a time-based blink",
    arguments: [(true, UInt32(0xff00_ff00)), (false, UInt32(0xff00_0f00))])
  func rawIndicator(_ high: Bool, _ color: UInt32) {
    let result = faceRender(faceSnapshot(signalHigh: high))
    for y in 2..<6 {
      for x in 58..<62 { #expect(result.pixels[y * 64 + x] == color) }
    }
    let other = faceRender(faceSnapshot(signalHigh: !high))
    #expect(
      result.pixels.enumerated().allSatisfy { index, pixel in
        faceRegions[0].contains(index) || pixel == other.pixels[index]
      })
  }

  @Test(
    "64x64 HH:MM renders leading zeros and day-boundary times with centered ink",
    arguments: [
      TimeInk(
        hour: 0, minute: 0, samples: [(8, 27), (20, 27), (39, 27), (51, 27)],
        edges: [
          (5, 34, 0xff80_0080), (9, 34, 0xff00_0000),
          (17, 34, 0xff80_0080), (21, 34, 0xff00_0000),
          (36, 34, 0xff80_0080), (40, 34, 0xff00_0000),
          (48, 34, 0xff80_0080), (52, 34, 0xff00_0000),
        ]),
      TimeInk(
        hour: 8, minute: 3, samples: [(8, 27), (20, 27), (39, 27), (51, 27)],
        edges: [
          (5, 34, 0xff80_0080), (9, 34, 0xff00_0000),
          (17, 34, 0xff00_0000), (21, 34, 0xff80_0080),
          (36, 34, 0xff80_0080), (40, 34, 0xff00_0000),
          (48, 34, 0xff00_0000), (52, 34, 0xff80_0080),
        ]),
      TimeInk(
        hour: 17, minute: 42, samples: [(9, 27), (17, 27), (42, 27), (51, 27)],
        edges: [
          (6, 34, 0xff00_0000), (10, 34, 0xff80_0080),
          (17, 34, 0xff00_0000), (21, 34, 0xff64_0064),
          (36, 34, 0xff22_0022), (40, 34, 0xff00_0000),
          (48, 34, 0xff00_0000), (52, 34, 0xff3d_003d),
        ]),
      TimeInk(
        hour: 23, minute: 59, samples: [(8, 27), (20, 27), (37, 27), (51, 27)],
        edges: [
          (5, 34, 0xff00_0000), (9, 34, 0xff3d_003d),
          (17, 34, 0xff00_0000), (21, 34, 0xff80_0080),
          (36, 34, 0xff6a_006a), (40, 34, 0xff45_0045),
          (48, 34, 0xff47_0047), (52, 34, 0xff5d_005d),
        ]),
      // Four's right bearing extends beyond its advance. 04:44 is
      // the archived overhang case, using the current font and layout.
      TimeInk(
        hour: 4, minute: 44, samples: [(8, 27), (23, 27), (42, 27), (54, 27)],
        edges: [
          (5, 34, 0xff80_0080), (9, 34, 0xff00_0000),
          (17, 34, 0xff22_0022), (21, 34, 0xff00_0000),
          (36, 34, 0xff22_0022), (40, 34, 0xff00_0000),
          (48, 34, 0xff22_0022), (52, 34, 0xff00_0000),
          (59, 37, 0xff0f_000f),
        ]),
    ])
  func timePlacement(_ fixture: TimeInk) {
    let pixels = faceRender(faceSnapshot(clock: faceClock(hour: fixture.hour, minute: fixture.minute))).pixels
    for (x, y) in fixture.samples { #expect(pixels[y * 64 + x] == 0xff80_0080) }
    expectFaceReferences(pixels, fixture.edges)
    #expect(pixels[30 * 64 + 30] == 0xff80_8080)
    let inkColumns = (0..<64).filter { x in (25..<43).contains { pixels[$0 * 64 + x] != 0xff00_0000 } }
    let left = inkColumns.first!
    let rightMargin = 63 - inkColumns.last!
    #expect(left >= 3 && rightMargin >= 3 && abs(left - rightMargin) <= 1)
  }

  @Test("Unacquired face renders red time and date placeholders with a blank timezone")
  func unacquiredComposition() {
    let pixels = faceRender(faceSnapshot(clock: .unknown)).pixels
    expectFaceReferences(
      pixels,
      [
        (7, 27, 0xffff_0000), (20, 27, 0xffff_0000),
        (40, 27, 0xffff_0000), (53, 27, 0xffff_0000), (30, 30, 0xff80_8080),
        (7, 47, 0xffff_0000), (13, 47, 0xffff_0000), (22, 47, 0xffff_0000), (28, 47, 0xffff_0000),
        (34, 47, 0xffff_0000), (43, 47, 0xffff_0000), (49, 47, 0xffff_0000), (55, 47, 0xffff_0000),
        (61, 47, 0xffff_0000),
      ])
    #expect((55..<64).allSatisfy { y in (42..<62).allSatisfy { pixels[y * 64 + $0] == 0xff00_0000 } })
    expectFaceWriteFootprint(pixels)
  }

  @Test(
    "Unknown evidence hides stored calendar values and timezone even after acquisition",
    arguments: [false, true], [false, true])
  func unknownStatesIgnoreCalendar(_ summerTime: Bool, _ acquired: Bool) {
    let clock = ClockSnapshot(
      calendarDateTime: faceClock(summerTime: summerTime).calendarDateTime,
      clockState: .unknown,
      hasAcquiredTime: acquired)
    #expect(faceRender(faceSnapshot(clock: clock)).pixels == faceRender(faceSnapshot(clock: .unknown)).pixels)
  }

  @Test("Missing time and date values use unknown colours even with confirmed evidence")
  func missingCalendarValuesRemainUnknown() {
    let clock = faceClock(calendar: ClockSnapshot.unknown.calendarDateTime)
    #expect(faceRender(faceSnapshot(clock: clock)).pixels == faceRender(faceSnapshot(clock: .unknown)).pixels)
  }

  @Test(
    "Partially unknown time preserves known field ink and independently centers the current glyphs",
    arguments: [true, false])
  func partialTime(_ unknownHour: Bool) {
    let clock = faceClock(field: unknownHour ? .hour : .minute, fieldState: .unknown)
    let pixels = faceRender(faceSnapshot(clock: clock)).pixels
    if unknownHour {
      expectFaceReferences(
        pixels,
        [
          (8, 27, 0xffff_0000), (21, 27, 0xffff_0000),
          (31, 30, 0xff80_8080), (43, 27, 0xff80_0080), (52, 27, 0xff80_0080),
        ])
    } else {
      expectFaceReferences(
        pixels,
        [
          (8, 27, 0xff80_0080), (16, 27, 0xff80_0080),
          (29, 30, 0xff80_8080), (39, 27, 0xffff_0000), (52, 27, 0xffff_0000),
        ])
    }
  }

  @Test(
    "64x64 date uses current Sept June and Oct labels with proportional centering and independent pixel references",
    arguments: [
      DateInk(
        month: 9,
        samples: [
          (3, 50, 0xff80_0080), (9, 49, 0xff80_0080), (18, 49, 0xff80_0080), (24, 50, 0xff80_0080),
          (32, 50, 0xff80_0080), (35, 49, 0xff80_0080), (44, 50, 0xff80_0080), (50, 49, 0xff80_0080),
          (56, 50, 0xff80_0080), (61, 49, 0xff80_0080),
        ]),
      DateInk(
        month: 6,
        samples: [
          (3, 49, 0xff80_0080), (8, 49, 0xff80_0080), (15, 51, 0xff80_0080), (25, 50, 0xff80_0080),
          (27, 50, 0xff80_0080), (35, 50, 0xff80_0080), (44, 50, 0xff80_0080), (50, 49, 0xff80_0080),
          (56, 50, 0xff80_0080), (61, 49, 0xff80_0080),
        ]),
      DateInk(
        month: 10,
        samples: [
          (5, 50, 0xff80_0080), (11, 49, 0xff80_0080), (22, 49, 0xff80_0080), (24, 50, 0xff80_0080),
          (31, 49, 0xff80_0080), (40, 50, 0xff80_0080), (46, 49, 0xff80_0080), (52, 50, 0xff80_0080),
          (58, 49, 0xff80_0080),
        ]),
    ])
  func datePlacement(_ fixture: DateInk) {
    let pixels = faceRender(faceSnapshot(clock: faceClock(month: fixture.month))).pixels
    expectFaceReferences(pixels, fixture.samples)
    #expect((47..<55).allSatisfy { y in pixels[y * 64] == 0xff00_0000 && pixels[y * 64 + 63] == 0xff00_0000 })
  }

  @Test(
    "Each clock date and timezone field chooses its own confidence tint without recoloring other components",
    arguments: FaceField.allCases, faceTintCases)
  func independentConfidence(_ field: FaceField, _ tint: TintInk) {
    let pixels = faceRender(faceSnapshot(clock: faceClock(field: field, fieldState: tint.state))).pixels
    let reference = faceRender(faceSnapshot()).pixels
    let (x, y, expected) = tint.reference(for: field)
    #expect(pixels[y * 64 + x] == expected)
    // Each visible character in the owning field must take the same state tint,
    // including both clock digits and every letter of the month word.
    let samples: [(Int, Int)] =
      switch field {
      case .hour: [(9, 27), (17, 27)]
      case .minute: [(42, 27), (51, 27)]
      case .day: [(3, 50), (9, 49)]
      case .month: [(18, 49), (24, 50), (32, 50), (35, 49)]
      case .year: [(44, 50), (50, 49), (56, 50), (61, 49)]
      case .zone: [(47, 59), (53, 59), (59, 57)]
      }
    for (inkX, inkY) in samples { #expect(pixels[inkY * 64 + inkX] == tint.opaque) }
    // Full comparison outside the owning component; within clock/date, fixed
    // reference pixels additionally distinguish the independently tinted fields.
    let region = faceRegions[field.regionIndex]
    #expect(pixels.enumerated().allSatisfy { index, pixel in region.contains(index) || pixel == reference[index] })
    for other in FaceField.allCases where other != field {
      let (otherX, otherY, otherColor) = faceTintCases[2].reference(for: other)
      #expect(pixels[otherY * 64 + otherX] == otherColor)
    }
    #expect(pixels[30 * 64 + 30] == 0xff80_8080)
  }

  @Test(
    "Unknown date fields use red placeholders without hiding the other date fields",
    arguments: [FaceField.day, .month, .year])
  func partialDate(_ field: FaceField) {
    let pixels = faceRender(faceSnapshot(clock: faceClock(field: field, fieldState: .unknown))).pixels
    switch field {
    case .day:
      expectFaceReferences(
        pixels,
        [
          (5, 48, 0xffff_0000), (11, 47, 0xffff_0000),
          (18, 49, 0xff80_0080), (24, 50, 0xff80_0080), (32, 50, 0xff80_0080), (35, 49, 0xff80_0080),
          (44, 50, 0xff80_0080), (50, 49, 0xff80_0080), (56, 50, 0xff80_0080), (61, 49, 0xff80_0080),
        ])
    case .month:
      expectFaceReferences(
        pixels,
        [
          (5, 50, 0xff80_0080), (11, 49, 0xff80_0080),
          (22, 47, 0xffff_0000), (28, 47, 0xffff_0000), (34, 47, 0xffff_0000),
          (41, 50, 0xff80_0080), (47, 49, 0xff80_0080), (53, 50, 0xff80_0080), (59, 49, 0xff80_0080),
        ])
    case .year:
      expectFaceReferences(
        pixels,
        [
          (3, 50, 0xff80_0080), (9, 49, 0xff80_0080),
          (18, 49, 0xff80_0080), (24, 50, 0xff80_0080), (32, 50, 0xff80_0080), (35, 49, 0xff80_0080),
          (46, 47, 0xffff_0000), (52, 47, 0xffff_0000), (58, 47, 0xffff_0000), (60, 47, 0xffff_0000),
        ])
    default: Issue.record("Not a date field")
    }
  }

  @Test(
    "64x64 GMT and BST are right aligned and use the timezone confidence including known false",
    arguments: [false, true], faceTintCases)
  func timezone(_ summerTime: Bool, _ tint: TintInk) {
    let pixels = faceRender(
      faceSnapshot(
        clock: faceClock(
          summerTime: summerTime,
          field: .zone, fieldState: tint.state))
    ).pixels
    let samples = summerTime ? [59 * 64 + 47, 59 * 64 + 53, 57 * 64 + 59] : [59 * 64 + 47, 59 * 64 + 51, 57 * 64 + 59]
    for offset in samples { #expect(pixels[offset] == tint.opaque) }
    #expect(
      (55..<64).allSatisfy { y in
        (0..<64).allSatisfy { x in (42..<62).contains(x) || pixels[y * 64 + x] == 0xff00_0000 }
      })
    #expect((42..<62).allSatisfy { pixels[63 * 64 + $0] == 0xff00_0000 })
  }

  @Test(
    "Unknown timezone leaves the cleared background regardless of the stored GMT or BST value",
    arguments: [false, true])
  func unknownTimezone(_ summerTime: Bool) {
    let pixels = faceRender(
      faceSnapshot(
        clock: faceClock(
          summerTime: summerTime,
          field: .zone, fieldState: .unknown))
    ).pixels
    #expect((55..<64).allSatisfy { y in (42..<62).allSatisfy { pixels[y * 64 + $0] == 0xff00_0000 } })
  }

  @Test("Later components preserve visible clock ink trace bits and date descenders")
  func layering() {
    let clockResult = faceRender(faceSnapshot(), times: Array(repeating: 1, count: 112) + [100])
    let dateResult = faceRender(faceSnapshot(), times: Array(repeating: 1, count: 122) + [100])
    #expect(!clockResult.completed && clockResult.reads == 113)
    #expect(!dateResult.completed && dateResult.reads == 123)
    let clockOnly = clockResult.pixels
    let throughDate = dateResult.pixels
    let complete = faceRender(faceSnapshot()).pixels
    #expect(clockOnly[27 * 64 + 9] == 0xff80_0080)
    #expect(clockOnly[50 * 64 + 3] == 0xff00_0000)
    #expect(throughDate[50 * 64 + 3] == 0xff80_0080)
    #expect(throughDate[59 * 64 + 47] == 0xff00_0000)
    #expect(Array(clockOnly[..<(43 * 64)]) == Array(complete[..<(43 * 64)]))
    #expect(Array(throughDate[..<(53 * 64)]) == Array(complete[..<(53 * 64)]))
    // Sept's p descender reaches the last row of the date frame.
    let descender = 53 * 64 + 28
    #expect(throughDate[descender] == 0xff80_0080)
    #expect(complete[descender] == throughDate[descender])
  }

  @Test("Repeated complete renders clear prior component ink and stale pixels outside component frames")
  func clearsPreviousComposition() {
    var old = faceRender(faceSnapshot()).pixels
    // Simulate a previous face's ink in every margin and gap.
    for index in old.indices where !faceRegions.contains(where: { $0.contains(index) }) {
      old[index] = 0xffff_ffff
    }
    let blank = MSFDisplaySnapshot(
      clockSnapshot: .unknown, secondPhaseBin: nil,
      timestamp: 0, signalHigh: false, highBins: 0, lowBins: 0)
    let reused = faceRender(blank, initial: old).pixels
    let fresh = faceRender(blank).pixels
    #expect(reused == fresh)
    expectFaceReferences(
      reused,
      [
        (58, 2, 0xff00_0f00), (3, 11, 0xff00_0f00),
        (4, 18, 0xff00_0f00), (49, 56, 0xff00_0000), (7, 27, 0xffff_0000),
      ])
  }

  @Test("Scene timestamp and calendar second do not drive an invented indicator blink or change minute formatting")
  func snapshotMetadata() {
    let ordinary = faceSnapshot()
    let different = MSFDisplaySnapshot(
      clockSnapshot: faceClock(second: 59),
      secondPhaseBin: ordinary.secondPhaseBin, timestamp: UInt64.max,
      signalHigh: ordinary.signalHigh, highBins: ordinary.highBins, lowBins: ordinary.lowBins,
      seconds: ordinary.seconds)
    #expect(faceRender(ordinary).pixels == faceRender(different).pixels)
  }

  @Test("A fixed received MSF frame projects into the complete face without changing raw diagnostics or earlier output")
  func modelToFaceComposition() throws {
    var model = MSFClockModel()
    let raw = faceSnapshot()
    // Independently established archived fixture: 2026-09-29, 17:42 BST.
    let frame = MSFCompletedFrame(
      aBits: 0x132_694b_c27e, bBits: 0x6,
      dataCount: 59, hasOpeningMarker: true, closingMarkerTime: raw.timestamp)
    let unacquired = MSFDisplaySnapshot(
      raw: raw,
      clockSnapshot: model.currentSnapshot(at: raw.timestamp) ?? .unknown)
    #expect(faceRender(unacquired).pixels == faceRender(faceSnapshot(clock: .unknown)).pixels)
    _ = model.receive(completedFrame: frame)
    let acquired = MSFDisplaySnapshot(
      raw: raw,
      clockSnapshot: try #require(model.currentSnapshot(at: raw.timestamp)))
    let earlier = faceRender(acquired).pixels
    #expect(earlier == faceRender(faceSnapshot()).pixels)

    let advancedRaw = MSFDisplaySnapshot(
      clockSnapshot: .unknown,
      secondPhaseBin: raw.secondPhaseBin, timestamp: raw.timestamp + 60_000_000,
      signalHigh: raw.signalHigh, highBins: raw.highBins, lowBins: raw.lowBins, seconds: raw.seconds)
    let projected = MSFDisplaySnapshot(
      raw: advancedRaw,
      clockSnapshot: try #require(model.currentSnapshot(at: advancedRaw.timestamp)))
    let later = faceRender(projected).pixels
    // Last numeral 2 -> 3: a fixed interior pixel changes independently
    // of the model's decoded value. Other date and raw components survive.
    #expect(earlier[34 * 64 + 52] == 0xff3d_003d)
    #expect(later[34 * 64 + 52] == 0xff80_0080)
    #expect(
      later.enumerated().allSatisfy { index, pixel in
        faceRegions[3].contains(index) || pixel == earlier[index]
      })
    #expect(projected.timestamp == advancedRaw.timestamp && projected.seconds == raw.seconds)
    #expect(
      projected.signalHigh == raw.signalHigh && projected.highBins == raw.highBins && projected.lowBins == raw.lowBins)
    #expect(faceRender(acquired).pixels == earlier)
    #expect(faceRender(unacquired).pixels == faceRender(faceSnapshot(clock: .unknown)).pixels)
  }
}

// Literal 64x64 component regions, independent of production LayoutMetrics.
// These exclude the initial full-frame background clear.
// The final rectangle extends past the bottom; only panel pixels are inspected.
private let faceSentinel: UInt32 = 0x1234_5678
private let faceRegions = [
  FaceRegion(x: 58..<62, y: 2..<6), FaceRegion(x: 2..<62, y: 8..<15),
  FaceRegion(x: 2..<62, y: 15..<23), FaceRegion(x: 0..<64, y: 25..<47),
  FaceRegion(x: 2..<62, y: 45..<54), FaceRegion(x: 42..<62, y: 55..<64),
]

private struct FaceRegion {
  let x: Range<Int>
  let y: Range<Int>
  func contains(_ index: Int) -> Bool { x.contains(index % 64) && y.contains(index / 64) }
}

private struct FaceRenderResult {
  let pixels: [UInt32]
  let completed: Bool
  let reads: Int
}

private struct TimeInk: Sendable {
  let hour: Int
  let minute: Int
  let samples: [(Int, Int)]
  let edges: [(Int, Int, UInt32)]
}

private struct DateInk: Sendable {
  let month: Int
  let samples: [(Int, Int, UInt32)]
}

private enum FaceField: CaseIterable, Sendable {
  case hour, minute, day, month, year, zone
  var regionIndex: Int {
    switch self {
    case .hour, .minute: 3
    case .day, .month, .year: 4
    case .zone: 5
    }
  }
}

// Fixed opaque ink samples for the six independently tinted fields.
private struct TintInk: Sendable {
  let state: EpistemicState
  let opaque: UInt32

  func reference(for field: FaceField) -> (Int, Int, UInt32) {
    switch field {
    case .hour: (9, 27, opaque)
    case .minute: (42, 27, opaque)
    case .day: (3, 50, opaque)
    case .month: (18, 49, opaque)
    case .year: (44, 50, opaque)
    case .zone: (47, 59, opaque)
    }
  }
}

private let faceTintCases = [
  TintInk(state: .candidate, opaque: 0xffff_6000),
  TintInk(state: .supported, opaque: 0xffff_c000),
  TintInk(state: .confirmed, opaque: 0xff80_0080),
]

private func faceClock(
  hour: Int = 17, minute: Int = 42, month: Int = 9, second: Int = 0,
  summerTime: Bool = true, state: EpistemicState = .confirmed,
  field: FaceField? = nil, fieldState: EpistemicState = .confirmed,
  calendar: CalendarDateTimeComponents? = nil
) -> ClockSnapshot {
  ClockSnapshot(
    calendarDateTime: calendar
      ?? CalendarDateTimeComponents(
        year: 2026, month: month, dayOfMonth: 29, dayOfWeek: 2,
        hour: hour, minute: minute, second: second, timeZone: (summerTime ? .bst : .gmt)),
    clockState: ClockState(
      year: field == .year ? fieldState : state,
      month: field == .month ? fieldState : state,
      dayOfMonth: field == .day ? fieldState : state, dayOfWeek: state,
      hour: field == .hour ? fieldState : state,
      minute: field == .minute ? fieldState : state,
      timeZone: field == .zone ? fieldState : state))
}

private func faceSnapshot(clock: ClockSnapshot = faceClock(), signalHigh: Bool = true) -> MSFDisplaySnapshot {
  MSFDisplaySnapshot(
    clockSnapshot: clock, secondPhaseBin: 0, timestamp: 420_000_000,
    signalHigh: signalHigh, highBins: 0b110, lowBins: 0b011,
    seconds: [
      .decoded(.minuteMarker), .unknown,
      .decoded(.bits(MSFBits(a: false, b: false))), .decoded(.bits(MSFBits(a: false, b: true))),
      .decoded(.bits(MSFBits(a: true, b: false))), .decoded(.bits(MSFBits(a: true, b: true))),
    ])
}

private func faceRender(
  _ snapshot: MSFDisplaySnapshot, times: [UInt64]? = nil,
  deadline: UInt64 = 100, initial: [UInt32]? = nil
) -> FaceRenderResult {
  let prefix: [UInt32] = [0xdead_beef, 0xcafe_babe, 0x1122_3344, 0x5566_7788]
  let suffix: [UInt32] = [0x99aa_bbcc, 0xddee_ff00, 0xface_feed, 0xbaad_f00d]
  var storage = prefix + (initial ?? Array(repeating: faceSentinel, count: 4096)) + suffix
  var completed = false
  var reads = 0
  storage.withUnsafeMutableBufferPointer { buffer in
    let framebuffer = UnsafeMutableBufferPointer(start: buffer.baseAddress!.advanced(by: 4), count: 4096)
    RenderHostTime.withTimestamps(times ?? Array(repeating: 1, count: 512)) {
      var context = DrawingContext(
        framebuffer: framebuffer, contextSize: PixelSize(width: 64, height: 64), pixelFormat: .bgrx8888,
        renderDeadline: RenderDeadline(timeUs: deadline))!
      completed =
        AnalyticalClockFace(
          size: PixelSize(width: 64, height: 64),
          configuration: ClockConfiguration(timeSource: .msf, theme: .standard, timeZone: .uk)
        ).render(
          into: &context, displaySnapshot: snapshot) && context.canContinue
      reads = RenderHostTime.readCount
    }
  }
  // Ordinary raster fixtures have no deadline pressure. Explicit scripts above
  // assert cancellation and read counts at individual drawing boundaries.
  if times == nil { #expect(completed) }
  #expect(Array(storage.prefix(4)) == prefix && Array(storage.suffix(4)) == suffix)
  return FaceRenderResult(pixels: Array(storage[4..<4100]), completed: completed, reads: reads)
}

private func expectFaceReferences(_ pixels: [UInt32], _ references: [(Int, Int, UInt32)]) {
  for (x, y, color) in references { #expect(pixels[y * 64 + x] == color) }
}

private func expectFaceWriteFootprint(_ pixels: [UInt32]) {
  // A completed render must initialise every panel pixel.
  #expect(pixels.allSatisfy { $0 != faceSentinel })

  // Nothing outside the six component regions may contain ink.
  #expect(
    pixels.enumerated().allSatisfy { index, pixel in
      faceRegions.contains { $0.contains(index) }
        || pixel == 0xff00_0000
    })
}

extension AnalyticalClockFaceTests {
  @Test(
    "All twelve month labels compose coherent dates at independently established 64x64 pen positions",
    arguments: monthScenes)
  fileprivate func allMonthLabels(_ scene: FaceScene) throws {
    let result = faceRender(faceSnapshot(clock: faceClock(calendar: scene.calendar)))
    let dateGlyphs = scene.date.withUTF8Buffer { $0.filter { $0 != 32 }.count }
    #expect(result.completed && result.reads == 115 + dateGlyphs)
    try expectSceneLabels(result.pixels, scene)
    // Month changes, including July/Aug descenders, cannot erase clock ink
    // or move the indicator, waveform and A/B history.
    let reference = faceRender(faceSnapshot()).pixels
    #expect(Array(result.pixels[..<(43 * 64)]) == Array(reference[..<(43 * 64)]))
    expectFaceWriteFootprint(result.pixels)
  }

  @Test(
    "Calendar boundary scenes replace the displayed time date and zone without stale ink",
    arguments: rolloverScenes)
  fileprivate func calendarRolloverComposition(_ transition: FaceTransition) throws {
    let before = faceSnapshot(clock: faceClock(calendar: transition.before.calendar))
    let after = faceSnapshot(clock: faceClock(calendar: transition.after.calendar))
    let first = faceRender(before)
    let next = faceRender(after, initial: first.pixels)
    #expect(first.completed && next.completed)
    try expectSceneLabels(first.pixels, transition.before)
    try expectSceneLabels(next.pixels, transition.after)
    #expect(Array(first.pixels[..<(25 * 64)]) == Array(next.pixels[..<(25 * 64)]))
    expectFaceWriteFootprint(next.pixels)
    // Fixed before/after snapshots deliberately test composition, not a
    // duplicate implementation of calendar arithmetic or BST transition rules.
  }

  @Test(
    "Every legal HH:MM keeps centered visible ink inside the current 64x64 clock frame",
    arguments: 0..<24, 0..<60)
  fileprivate func everyTimeFits(_ hour: Int, _ minute: Int) throws {
    let result = faceRender(faceSnapshot(clock: faceClock(hour: hour, minute: minute)))
    #expect(result.completed)
    let columns = (0..<64).filter { x in
      (25..<43).contains { y in result.pixels[y * 64 + x] != UInt32(0xff00_0000) }
    }
    let left = try #require(columns.first)
    let right = try #require(columns.last)
    let rightMargin = 63 - right
    let width = right - left + 1
    #expect(left >= 3 && rightMargin >= 3)
    #expect(abs(left - rightMargin) <= 1)
    #expect((54...56).contains(width))
    // Geometry only: font/primitive suites already verify glyph rasters.
    // The old requirement that unknown and known fields have fixed slots
    // is intentionally absent; the face centers the actual visible ink.
  }

  @Test(
    "Longest date label clips to its frame at calendar boundaries without disturbing the zone",
    arguments: dateBoundaryScenes)
  fileprivate func dateBoundaryPlacement(_ scene: FaceScene) throws {
    let result = faceRender(faceSnapshot(clock: faceClock(calendar: scene.calendar)))
    #expect(result.completed)
    try expectSceneLabels(result.pixels, scene)
    expectFaceWriteFootprint(result.pixels)
  }

  @Test("Mixed unknown day and year with candidate Oct preserves supported hour confirmed minute and blank zone")
  fileprivate func mixedDateStates() {
    let calendar = faceCalendar(2026, 10, 1, 4, 17, 42, true)
    let clock = ClockSnapshot(
      calendarDateTime: calendar,
      clockState: ClockState(
        year: .unknown, month: .candidate, dayOfMonth: .unknown, dayOfWeek: .confirmed,
        hour: .supported, minute: .confirmed, timeZone: .unknown))
    let pixels = faceRender(faceSnapshot(clock: clock)).pixels
    // The 59-pixel label fits in the 60-pixel date frame.
    expectFaceReferences(
      pixels,
      [
        (7, 47, 0xffff_0000), (13, 47, 0xffff_0000),
        (22, 49, 0xffff_6000), (24, 50, 0xffff_6000), (31, 49, 0xffff_6000),
        (42, 47, 0xffff_0000), (48, 47, 0xffff_0000), (54, 47, 0xffff_0000), (60, 47, 0xffff_0000),
        (9, 27, 0xffff_c000), (17, 27, 0xffff_c000),
        (42, 27, 0xff80_0080), (51, 27, 0xff80_0080), (30, 30, 0xff80_8080),
      ])
    #expect((55..<64).allSatisfy { y in (42..<62).allSatisfy { pixels[y * 64 + $0] == 0xff00_0000 } })
  }
}

private struct FaceScene: Sendable {
  let calendar: CalendarDateTimeComponents
  let date: StaticString
  let dateX: Int
  let time: StaticString
}

private struct FaceTransition: Sendable {
  let name: String
  let before: FaceScene
  let after: FaceScene
}

// Independent label spellings, measured advances and baseline positions.
// 2026 first-of-month weekdays use the calendar's Sunday=0 convention.
private let monthScenes = [
  FaceScene(calendar: faceCalendar(2026, 1, 1, 4, 17, 42, false), date: "01 Jan 2026", dateX: 2, time: "17:42"),
  FaceScene(calendar: faceCalendar(2026, 2, 1, 0, 17, 42, false), date: "01 Feb 2026", dateX: 2, time: "17:42"),
  FaceScene(calendar: faceCalendar(2026, 3, 1, 0, 17, 42, false), date: "01 Mar 2026", dateX: 1, time: "17:42"),
  FaceScene(calendar: faceCalendar(2026, 4, 1, 3, 17, 42, true), date: "01 Apr 2026", dateX: 2, time: "17:42"),
  FaceScene(calendar: faceCalendar(2026, 5, 1, 5, 17, 42, true), date: "01 May 2026", dateX: 1, time: "17:42"),
  FaceScene(calendar: faceCalendar(2026, 6, 1, 1, 17, 42, true), date: "01 June 2026", dateX: -1, time: "17:42"),
  FaceScene(calendar: faceCalendar(2026, 7, 1, 3, 17, 42, true), date: "01 July 2026", dateX: 0, time: "17:42"),
  FaceScene(calendar: faceCalendar(2026, 8, 1, 6, 17, 42, true), date: "01 Aug 2026", dateX: 2, time: "17:42"),
  FaceScene(calendar: faceCalendar(2026, 9, 1, 2, 17, 42, true), date: "01 Sept 2026", dateX: 0, time: "17:42"),
  FaceScene(calendar: faceCalendar(2026, 10, 1, 4, 17, 42, true), date: "01 Oct 2026", dateX: 2, time: "17:42"),
  FaceScene(calendar: faceCalendar(2026, 11, 1, 0, 17, 42, false), date: "01 Nov 2026", dateX: 2, time: "17:42"),
  FaceScene(calendar: faceCalendar(2026, 12, 1, 2, 17, 42, false), date: "01 Dec 2026", dateX: 2, time: "17:42"),
]

private let rolloverScenes = [
  FaceTransition(
    name: "minute and hour",
    before:
      FaceScene(calendar: faceCalendar(2026, 9, 29, 2, 12, 59, true), date: "29 Sept 2026", dateX: 0, time: "12:59"),
    after:
      FaceScene(calendar: faceCalendar(2026, 9, 29, 2, 13, 0, true), date: "29 Sept 2026", dateX: 0, time: "13:00")),
  FaceTransition(
    name: "midnight",
    before:
      FaceScene(calendar: faceCalendar(2026, 9, 29, 2, 23, 59, true), date: "29 Sept 2026", dateX: 0, time: "23:59"),
    after:
      FaceScene(calendar: faceCalendar(2026, 9, 30, 3, 0, 0, true), date: "30 Sept 2026", dateX: 0, time: "00:00")),
  FaceTransition(
    name: "month",
    before:
      FaceScene(calendar: faceCalendar(2026, 9, 30, 3, 23, 59, true), date: "30 Sept 2026", dateX: 0, time: "23:59"),
    after:
      FaceScene(calendar: faceCalendar(2026, 10, 1, 4, 0, 0, true), date: "01 Oct 2026", dateX: 2, time: "00:00")),
  FaceTransition(
    name: "year",
    before:
      FaceScene(calendar: faceCalendar(2026, 12, 31, 4, 23, 59, false), date: "31 Dec 2026", dateX: 2, time: "23:59"),
    after:
      FaceScene(calendar: faceCalendar(2027, 1, 1, 5, 0, 0, false), date: "01 Jan 2027", dateX: 2, time: "00:00")),
  FaceTransition(
    name: "enter leap day",
    before:
      FaceScene(calendar: faceCalendar(2028, 2, 28, 1, 23, 59, false), date: "28 Feb 2028", dateX: 2, time: "23:59"),
    after:
      FaceScene(calendar: faceCalendar(2028, 2, 29, 2, 0, 0, false), date: "29 Feb 2028", dateX: 2, time: "00:00")),
  FaceTransition(
    name: "leave leap day",
    before:
      FaceScene(calendar: faceCalendar(2028, 2, 29, 2, 23, 59, false), date: "29 Feb 2028", dateX: 2, time: "23:59"),
    after:
      FaceScene(calendar: faceCalendar(2028, 3, 1, 3, 0, 0, false), date: "01 Mar 2028", dateX: 1, time: "00:00")),
  FaceTransition(
    name: "non-leap February",
    before:
      FaceScene(calendar: faceCalendar(2027, 2, 28, 0, 23, 59, false), date: "28 Feb 2027", dateX: 2, time: "23:59"),
    after:
      FaceScene(calendar: faceCalendar(2027, 3, 1, 1, 0, 0, false), date: "01 Mar 2027", dateX: 1, time: "00:00")),
  FaceTransition(
    name: "GMT to BST",
    before:
      FaceScene(calendar: faceCalendar(2026, 3, 29, 0, 0, 59, false), date: "29 Mar 2026", dateX: 1, time: "00:59"),
    after:
      FaceScene(calendar: faceCalendar(2026, 3, 29, 0, 2, 0, true), date: "29 Mar 2026", dateX: 1, time: "02:00")),
  FaceTransition(
    name: "BST to GMT",
    before:
      FaceScene(calendar: faceCalendar(2026, 10, 25, 0, 1, 59, true), date: "25 Oct 2026", dateX: 2, time: "01:59"),
    after:
      FaceScene(calendar: faceCalendar(2026, 10, 25, 0, 1, 0, false), date: "25 Oct 2026", dateX: 2, time: "01:00")),
]

private let dateBoundaryScenes = [
  FaceScene(calendar: faceCalendar(2000, 6, 1, 4, 17, 42, true), date: "01 June 2000", dateX: -1, time: "17:42"),
  FaceScene(calendar: faceCalendar(2000, 6, 30, 5, 17, 42, true), date: "30 June 2000", dateX: -1, time: "17:42"),
  FaceScene(calendar: faceCalendar(2099, 6, 1, 1, 17, 42, true), date: "01 June 2099", dateX: -1, time: "17:42"),
  FaceScene(calendar: faceCalendar(2099, 6, 30, 2, 17, 42, true), date: "30 June 2099", dateX: -1, time: "17:42"),
  // Together with boundary/rollover scenes, this exercises all ten PixelOperator8Font
  // digits in composed dates. June is one of the widest labels;
  // fixed digit advances make the old 37,200-width loop unnecessary.
  FaceScene(calendar: faceCalendar(2045, 6, 14, 3, 17, 42, true), date: "14 June 2045", dateX: -1, time: "17:42"),
]

private func faceCalendar(
  _ year: Int, _ month: Int, _ day: Int, _ weekday: Int,
  _ hour: Int, _ minute: Int, _ summerTime: Bool
) -> CalendarDateTimeComponents {
  CalendarDateTimeComponents(
    year: year, month: month, dayOfMonth: day, dayOfWeek: weekday,
    hour: hour, minute: minute, second: 0, timeZone: (summerTime ? .bst : .gmt))
}

// Reuse the independently tested font/text primitives as the composition
// oracle. Expected labels and pens are literal fixture values; no clock-face
// formatter, measurement or centering helper supplies these expectations.
// Compare diagnostic raster rows rather than repeating exhaustive glyph tests.
private func expectSceneLabels(_ pixels: [UInt32], _ scene: FaceScene) throws {
  var reference = Array(repeating: UInt32(0xff00_0000), count: 4096)
  let bytes = scene.time.withUTF8Buffer { Array($0) }
  #expect(bytes.count == 5)
  try reference.withUnsafeMutableBufferPointer { buffer in
    var context = DrawingContext(
      framebuffer: buffer, contextSize: PixelSize(width: 64, height: 64), pixelFormat: .bgrx8888)!
    context.drawString(
      scene.date, font: PixelOperator8Font.self,
      atPen: PixelPoint(x: scene.dateX, y: 53), color: .purple,
      clippedTo: PixelRect(x: 2, y: 45, width: 60, height: 9))
    let offsets = [0, 12, 24, 31, 43]
    for index in 0..<5 {
      let code = index == 2 ? UInt32(0xa789) : UInt32(bytes[index])
      let scalar = try #require(Unicode.Scalar(code))
      let glyph = try #require(ClockFont.glyph(for: scalar))
      context.drawGlyph(
        glyph,
        atPen: PixelPoint(x: 4 + offsets[index], y: 42),
        color: index == 2 ? .gray : .purple)
    }
    let zone: StaticString = (scene.calendar.timeZone == .bst) ? "BST" : "GMT"
    context.drawString(
      zone, font: PixelOperator8Font.self,
      atPen: PixelPoint(x: (scene.calendar.timeZone == .bst) ? 44 : 42, y: 63), color: .purple,
      clippedTo: PixelRect(x: 42, y: 55, width: 20, height: 9))
  }
  for y in [27, 34, 42] {
    #expect(Array(pixels[(y * 64)..<(y * 64 + 64)]) == Array(reference[(y * 64)..<(y * 64 + 64)]))
  }
  for y in 45..<54 {
    let start = y * 64 + 2
    #expect(Array(pixels[start..<(start + 60)]) == Array(reference[start..<(start + 60)]))
  }
  for y in 55..<64 {
    let start = y * 64 + 42
    #expect(Array(pixels[start..<(start + 20)]) == Array(reference[start..<(start + 20)]))
  }
}
