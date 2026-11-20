//
//  MSFABRenderingTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

private let abSentinel: UInt32 = 0x1234_5678
// Small independent pair images, including the single blank column between
// A and B. Glyph data/measurement itself is covered by the existing font suite.
private let abZeroZero = ["1110111", "1010101", "1010101", "1010101", "1110111"]
private let abZeroOne = ["1110010", "1010110", "1010010", "1010010", "1110111"]
private let abOneZero = ["0100111", "1100101", "0100101", "0100101", "1110111"]
private let abOneOne = ["0100010", "1100110", "0100010", "0100010", "1110111"]
private let abUnknown = ["1110111", "0010001", "0110011", "0000000", "0100010"]
private let abMarker = ["1010101", "1110111", "1110111", "1010101", "1010101"]

@Test(
  "MSF bit rendering maps all decoded pairs unknown absent and marker seconds to the current glyphs",
  arguments: [
    (MSFDisplaySecond.decoded(.bits(MSFBits(a: false, b: false))), abZeroZero),
    (.decoded(.bits(MSFBits(a: false, b: true))), abZeroOne),
    (.decoded(.bits(MSFBits(a: true, b: false))), abOneZero),
    (.decoded(.bits(MSFBits(a: true, b: true))), abOneOne),
    (.unknown, abUnknown), (.decoded(.minuteMarker), abMarker),
    (.absent, ["0000000", "0000000", "0000000", "0000000", "0000000"]),
  ] as [(MSFDisplaySecond, [String])])
func abRenderingSecondGlyphs(_ second: MSFDisplaySecond, _ rows: [String]) {
  var seconds: [MSFDisplaySecond] = Array(repeating: .absent, count: 6)
  seconds[0] = second
  let pixels = abPixels(abSnapshot(seconds: seconds, phase: 0))
  // Pen x=4, baseline=23, top=18. A occupies x=4...6 and B x=8...10.
  expectABPixels(pixels, patches: [(4, rows)])
}

@Test("MSF bit rendering clears history when phase is unknown instead of inventing alignment")
func abRenderingUnknownPhase() {
  let pixels = abPixels(abSnapshot(seconds: Array(repeating: .unknown, count: 6), phase: nil))
  expectABPixels(pixels, patches: [])
}

@Test("MSF bit rendering keeps absent seconds blank while an unknown second has question glyphs")
func abRenderingAbsentAndUnknown() {
  let pixels = abPixels(abSnapshot(seconds: [.absent, .unknown, .absent, .absent, .absent, .absent], phase: 0))
  expectABPixels(pixels, patches: [(14, abUnknown)])
}

@Test("MSF bit rendering preserves physical ordering and gaps across the six slots")
func abRenderingPhysicalOrder() {
  let snapshot = abSnapshot(
    seconds: [
      .decoded(.bits(MSFBits(a: false, b: true))),
      .decoded(.bits(MSFBits(a: true, b: false))),
      .unknown, .decoded(.minuteMarker), .absent,
      .decoded(.bits(MSFBits(a: true, b: true))),
    ], phase: 0)
  expectABPixels(
    abPixels(snapshot),
    patches: [
      (4, abZeroOne), (14, abOneZero), (24, abUnknown), (34, abMarker), (54, abOneOne),
    ])
}

@Test(
  "MSF bit phase positions zero through nine clip the oldest pair and reveal the unfinished pair",
  arguments: [
    (0, 4, 54, 64), (1, 3, 53, 63), (2, 2, 52, 62), (3, 1, 51, 61),
    (4, 0, 50, 60), (5, -1, 49, 59), (6, -2, 48, 58), (7, -3, 47, 57),
    (8, -4, 46, 56), (9, -5, 45, 55),
  ] as [(Int, Int, Int, Int)])
func abRenderingPhase(_ phase: Int, _ oldestX: Int, _ newestX: Int, _ unfinishedX: Int) {
  let snapshot = abSnapshot(
    seconds: [
      .decoded(.bits(MSFBits(a: false, b: false))), .absent, .absent, .absent, .absent,
      .decoded(.bits(MSFBits(a: true, b: true))),
    ], phase: phase)
  // Literal expected starts, not a call to the production placement helper.
  expectABPixels(
    abPixels(snapshot),
    patches: [
      (oldestX, abZeroZero), (newestX, abOneOne), (unfinishedX, abUnknown),
    ])
}

@Test(
  "MSF empty completed history still reveals the additional unfinished slot as phase advances",
  arguments: [(0, 64), (2, 62), (3, 61), (9, 55)] as [(Int, Int)])
func abRenderingUnfinishedOnly(_ phase: Int, _ expectedX: Int) {
  let snapshot = abSnapshot(seconds: Array(repeating: .absent, count: 6), phase: phase)
  expectABPixels(abPixels(snapshot), patches: [(expectedX, abUnknown)])
}

@Test("MSF bit rendering clears previous glyphs when a later snapshot has no aligned history")
func abRenderingClearsPrevious() {
  let pixels = abBuffer { context in
    let face = AnalyticalClockFace(
      size: PixelSize(width: 64, height: 64),
      configuration: ClockConfiguration(timeSource: .msf, theme: .standard, timeZone: .uk)
    )
    face.drawBits(
      into: &context,
      displaySnapshot: abSnapshot(seconds: Array(repeating: .unknown, count: 6), phase: 9), theme: .standard)
    face.drawBits(
      into: &context,
      displaySnapshot: abSnapshot(seconds: Array(repeating: .absent, count: 6), phase: nil), theme: .standard)
  }
  expectABPixels(pixels, patches: [])
}

@Test("MSF trace and bit component draws preserve each other's pixels and the two-row clock gap")
func abRenderingComponentPreservation() {
  let snapshot = abSnapshot(seconds: [.decoded(.minuteMarker), .absent, .absent, .absent, .absent, .absent], phase: 0)
  let pixels = abBuffer { context in
    let face = AnalyticalClockFace(
      size: PixelSize(width: 64, height: 64),
      configuration: ClockConfiguration(timeSource: .msf, theme: .standard, timeZone: .uk)
    )
    let trace = MSFDisplaySnapshot(
      clockSnapshot: .unknown, secondPhaseBin: nil,
      timestamp: 6_000_000, signalHigh: true, highBins: 0x0800_0000_0000_0000,
      lowBins: 0x0fff_ffff_ffff_ffff)
    face.drawTrace(into: &context, displaySnapshot: trace, theme: .standard)
    let beforeBits = Array(context.framebuffer)
    face.drawBits(into: &context, displaySnapshot: snapshot, theme: .standard)
    for y in 0..<64 where !(15..<23).contains(y) {
      for x in 0..<64 { #expect(context.framebuffer[y * 64 + x] == beforeBits[y * 64 + x]) }
    }
    let beforeTrace = Array(context.framebuffer)
    face.drawTrace(into: &context, displaySnapshot: trace, theme: .standard)
    for y in 0..<64 where !(8..<15).contains(y) {
      for x in 0..<64 { #expect(context.framebuffer[y * 64 + x] == beforeTrace[y * 64 + x]) }
    }
  }
  for y in 8..<15 {
    for x in 2..<62 {
      #expect(pixels[y * 64 + x] == (y == 14 || x == 61 ? 0xff00_ff00 : 0xff00_0f00))
    }
  }
  for y in 23..<25 {
    #expect(pixels[(y * 64)..<((y + 1) * 64)].allSatisfy { $0 == abSentinel })
  }
  #expect(pixels[18 * 64 + 4] == 0xff00_ff00 && pixels[18 * 64 + 5] == 0xff00_0f00)
}

// All edge-driven tests extend the existing serialized scanner suite. They
// share its per-case recorder reset rather than an independently serialized suite.
extension MSFScanTests {
  @Test("MSF scanner completed pairs retain their rendered order after display-ring rollover", arguments: [6, 12])
  func abRenderingScannerRollover(_ count: Int) {
    let pairs = [
      MSFBits(a: true, b: false), MSFBits(a: false, b: true),
      MSFBits(a: true, b: true), MSFBits(a: false, b: false),
      MSFBits(a: false, b: true), MSFBits(a: true, b: false),
    ]
    var scan = MSFScan()
    scan.receiveSignalChange(.falling, at: 100_000)
    for index in 0..<count {
      abEmitPair(pairs[index % 6], into: &scan, at: UInt64(index + 1) * 1_000_000)
    }
    let now = UInt64(count + 1) * 1_000_000
    scan.receiveSignalChange(.rising, at: now)
    let snapshot = scan.displaySnapshot(at: now)
    #expect(snapshot.secondPhaseBin == 0)
    for index in 0..<6 { #expect(snapshot.seconds[index] == .decoded(.bits(pairs[index]))) }
    expectABPixels(
      abPixels(snapshot),
      patches: [
        (4, abOneZero), (14, abZeroOne), (24, abOneOne),
        (34, abZeroZero), (44, abZeroOne), (54, abOneZero),
      ])
  }

  @Test("MSF scanner phase-recovery gaps damage and marker snapshots render distinct physical slots")
  func abRenderingScannerGaps() {
    var scan = MSFScan()
    scan.receiveSignalChange(.falling, at: 100_000)
    abEmitPair(MSFBits(a: true, b: false), into: &scan, at: 1_000_000)
    abEmitPair(MSFBits(a: false, b: true), into: &scan, at: 4_000_000)
    scan.receiveSignalChange(.rising, at: 5_000_000)
    scan.receiveSignalChange(.falling, at: 5_138_438)
    scan.receiveSignalChange(.rising, at: 6_000_000)
    scan.receiveSignalChange(.falling, at: 6_500_000)
    scan.receiveSignalChange(.rising, at: 7_000_000)
    let snapshot = scan.displaySnapshot(at: 7_000_000)
    #expect(snapshot.secondPhaseBin == 0)
    #expect(snapshot.seconds[1] == .absent && snapshot.seconds[2] == .absent)
    #expect(snapshot.seconds[4] == .unknown && snapshot.seconds[5] == .decoded(.minuteMarker))
    expectABPixels(
      abPixels(snapshot),
      patches: [
        (4, abOneZero), (34, abZeroOne), (44, abUnknown), (54, abMarker),
      ])
  }
}

private func abSnapshot(seconds: [MSFDisplaySecond], phase: Int?) -> MSFDisplaySnapshot {
  var slots: InlineArray<6, MSFDisplaySecond> = .init(repeating: .absent)
  for (index, second) in seconds.enumerated() { slots[index] = second }
  return MSFDisplaySnapshot(
    clockSnapshot: .unknown, secondPhaseBin: phase,
    timestamp: 6_000_000, signalHigh: false, highBins: 0, lowBins: 0, seconds: slots)
}

private func abPixels(_ snapshot: MSFDisplaySnapshot) -> [UInt32] {
  abBuffer { context in
    AnalyticalClockFace(
      size: PixelSize(width: 64, height: 64),
      configuration: ClockConfiguration(timeSource: .msf, theme: .standard, timeZone: .uk)
    ).drawBits(
      into: &context, displaySnapshot: snapshot, theme: .standard)
  }
}

private func abBuffer(_ draw: (inout DrawingContext) -> Void) -> [UInt32] {
  let prefix: [UInt32] = [0xdead_beef, 0xcafe_babe, 0x1122_3344, 0x5566_7788]
  let suffix: [UInt32] = [0x99aa_bbcc, 0xddee_ff00, 0xface_feed, 0xbaad_f00d]
  var storage = prefix + Array(repeating: abSentinel, count: 4096) + suffix
  storage.withUnsafeMutableBufferPointer { buffer in
    var context = DrawingContext(
      framebuffer: UnsafeMutableBufferPointer(
        start: buffer.baseAddress!.advanced(by: 4), count: 4096), contextSize: PixelSize(width: 64, height: 64),
      pixelFormat: .bgrx8888)!
    draw(&context)
  }
  #expect(Array(storage.prefix(4)) == prefix && Array(storage.suffix(4)) == suffix)
  return Array(storage[4..<4100])
}

// Compare fixed seven-column pair images at literal expected starts. This
// reads no production glyph, measurement, layout or phase-placement helper.
private func expectABPixels(_ pixels: [UInt32], patches: [(Int, [String])]) {
  let images = patches.map { ($0.0, $0.1.map { Array($0.utf8) }) }
  for y in 0..<64 {
    for x in 0..<64 {
      var expected = abSentinel
      if (2..<62).contains(x) && (15..<23).contains(y) {
        expected = 0xff00_0f00
        if (18..<23).contains(y) {
          for (start, rows) in images where x >= start && x < start + 7 {
            if rows[y - 18][x - start] == 49 { expected = 0xff00_ff00 }
          }
        }
      }
      #expect(pixels[y * 64 + x] == expected)
    }
  }
}

private func abEmitPair(_ pair: MSFBits, into scan: inout MSFScan, at start: UInt64) {
  scan.receiveSignalChange(.rising, at: start)
  if pair.a {
    scan.receiveSignalChange(.falling, at: start + (pair.b ? 300_000 : 200_000))
  } else {
    scan.receiveSignalChange(.falling, at: start + 100_000)
    if pair.b {
      scan.receiveSignalChange(.rising, at: start + 200_000)
      scan.receiveSignalChange(.falling, at: start + 300_000)
    }
  }
}
