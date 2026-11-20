//
//  MSFABDisplaySnapshotTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

// Fixed mixed sequence from the archived display test, oldest to newest.
private let displayPairs = [
  MSFBits(a: true, b: false), MSFBits(a: false, b: true),
  MSFBits(a: true, b: true), MSFBits(a: false, b: false),
  MSFBits(a: false, b: true), MSFBits(a: true, b: false),
]

@Test("MSF display snapshots distinguish absent, unknown, marker and all decoded pairs")
func displaySecondRepresentation() {
  #expect(MSFDisplaySnapshot.binCount == 60 && MSFDisplaySnapshot.binDuration == 100_000)
  #expect(MSFDisplaySnapshot.secondCount == 6)
  let absent = MSFDisplaySecond.absent
  let unknown = MSFDisplaySecond.unknown
  let marker = MSFDisplaySecond.decoded(.minuteMarker)
  #expect(absent != unknown && unknown != marker && marker != absent)
  for a in [false, true] {
    for b in [false, true] {
      let value = MSFDisplaySecond.decoded(.bits(MSFBits(a: a, b: b)))
      #expect(value != absent && value != unknown && value != marker)
      #expect(value == .decoded(.bits(MSFBits(a: a, b: b))))
      #expect(value != .decoded(.bits(MSFBits(a: !a, b: b))))
      #expect(value != .decoded(.bits(MSFBits(a: a, b: !b))))
    }
  }
}

@Test(
  "MSF display clock merge preserves every raw field and second representation",
  arguments: [Optional<Int>.none, 0, 9])
func displaySnapshotClockMerge(_ phase: Int?) {
  var seconds: InlineArray<6, MSFDisplaySecond> = .init(repeating: .absent)
  seconds[1] = .unknown
  seconds[2] = .decoded(.minuteMarker)
  seconds[3] = .decoded(.bits(MSFBits(a: false, b: true)))
  seconds[4] = .decoded(.bits(MSFBits(a: true, b: false)))
  seconds[5] = .decoded(.bits(MSFBits(a: true, b: true)))
  let raw = MSFDisplaySnapshot(
    clockSnapshot: .unknown, secondPhaseBin: phase,
    timestamp: 7_020_000, signalHigh: true,
    highBins: 0x0aaa_aaaa_aaaa_aaaa, lowBins: 0x0555_5555_5555_5555,
    seconds: seconds)
  let calendar = CalendarDateTimeComponents(
    year: 2026, month: 9, dayOfMonth: 29, dayOfWeek: 2,
    hour: 17, minute: 42, second: 3, timeZone: .bst)
  let state = ClockState(
    year: .confirmed, month: .supported, dayOfMonth: .candidate,
    dayOfWeek: .unknown, hour: .confirmed, minute: .supported, timeZone: .candidate)
  let clock = ClockSnapshot(calendarDateTime: calendar, clockState: state)
  let merged = MSFDisplaySnapshot(raw: raw, clockSnapshot: clock)
  #expect(merged.timestamp == 7_020_000 && merged.signalHigh)
  #expect(merged.highBins == 0x0aaa_aaaa_aaaa_aaaa && merged.lowBins == 0x0555_5555_5555_5555)
  #expect(merged.secondPhaseBin == phase)
  #expect(
    displaySlots(merged) == [
      .absent, .unknown, .decoded(.minuteMarker),
      .decoded(.bits(MSFBits(a: false, b: true))),
      .decoded(.bits(MSFBits(a: true, b: false))),
      .decoded(.bits(MSFBits(a: true, b: true))),
    ])
  #expect(merged.clockSnapshot.calendarDateTime == calendar)
  #expect(merged.clockSnapshot.clockState.year == .confirmed)
  #expect(merged.clockSnapshot.clockState.month == .supported)
  #expect(merged.clockSnapshot.clockState.dayOfMonth == .candidate)
  #expect(merged.clockSnapshot.clockState.dayOfWeek == .unknown)
  #expect(merged.clockSnapshot.clockState.hour == .confirmed)
  #expect(merged.clockSnapshot.clockState.minute == .supported)
  #expect(merged.clockSnapshot.clockState.timeZone == .candidate)
  #expect(raw.clockSnapshot.clockState.year == .unknown)
  let defaults = MSFDisplaySnapshot(
    clockSnapshot: .unknown, secondPhaseBin: nil,
    timestamp: 0, signalHigh: false, highBins: 0, lowBins: 0)
  #expect(displaySlots(defaults) == Array(repeating: .absent, count: 6))
}

// Extending this suite keeps all edge-driven tests under the SAME serialized
// parent as MSFScanTests. Its initializer resets output capture for every case.
extension MSFScanTests {
  @Test(
    "MSF A/B display exposes completed pairs only after the next observed start",
    arguments: [
      MSFBits(a: false, b: false), MSFBits(a: false, b: true),
      MSFBits(a: true, b: false), MSFBits(a: true, b: true),
    ])
  func displayPairClosure(_ pair: MSFBits) {
    var scan = MSFScan()
    scan.receiveSignalChange(.falling, at: 100_000)
    emitDisplayPair(pair, into: &scan, at: 1_000_000)
    #expect(displaySlots(scan.displaySnapshot(at: 1_900_000)) == Array(repeating: .absent, count: 6))
    #expect(displaySlots(scan.displaySnapshot(at: 2_000_000)) == Array(repeating: .absent, count: 6))
    scan.receiveSignalChange(.rising, at: 2_000_000)
    #expect(
      displaySlots(scan.displaySnapshot(at: 2_000_000)) == [
        .absent, .absent, .absent, .absent, .absent, .decoded(.bits(pair)),
      ])
    #expect(scan.recordedCount == 1 && scan.recordedSecond(at: 0) == .bits(pair))
  }

  @Test("MSF A/B display mixed pairs retain physical order and agree with scanner history")
  func displayMixedPairs() {
    var scan = displaySixPairs()
    let snapshot = scan.displaySnapshot(at: 7_000_000)
    #expect(displaySlots(snapshot) == displayPairs.map { .decoded(.bits($0)) })
    #expect(snapshot.secondPhaseBin == 0 && snapshot.timestamp == 7_000_000)
    #expect(snapshot.clockSnapshot.clockState.hour == .unknown)
    for index in 0..<6 {
      #expect(scan.recordedSecond(at: index) == .bits(displayPairs[index]))
    }
  }

  @Test(
    "MSF A/B display completed slots advance on the second grid rather than raw sample ticks",
    arguments: [
      (UInt64(7_000_000), 0, false), (7_019_999, 0, false), (7_020_000, 0, false),
      (7_100_000, 1, false), (7_999_999, 9, false), (8_000_000, 0, true),
    ])
  func displayGridScrolling(_ now: UInt64, _ phase: Int, _ shifted: Bool) {
    var scan = displaySixPairs()
    let snapshot = scan.displaySnapshot(at: now)
    let expected: [MSFDisplaySecond] =
      shifted
      ? displayPairs.dropFirst().map { .decoded(.bits($0)) } + [.absent]
      : displayPairs.map { .decoded(.bits($0)) }
    #expect(displaySlots(snapshot) == expected && snapshot.secondPhaseBin == phase)
  }

  @Test(
    "MSF A/B display phase bins respect timestamp quantization and a non-boot-aligned anchor",
    arguments: [
      (UInt64(1_020_000), Optional<Int>.none), (1_039_999, nil),
      (1_040_000, 0), (1_119_999, 0), (1_120_000, 0), (1_140_000, 1),
      (1_920_000, 8), (1_940_000, 9), (2_020_000, 9), (2_040_000, 0),
    ])
  func displayOffsetPhaseBins(_ now: UInt64, _ phase: Int?) {
    var scan = MSFScan()
    scan.receiveSignalChange(.falling, at: 125_000)
    emitDisplayPair(displayPairs[0], into: &scan, at: 1_025_000)
    let snapshot = scan.displaySnapshot(at: now)
    #expect(snapshot.secondPhaseBin == phase)
    #expect(displaySlots(snapshot) == Array(repeating: .absent, count: 6))
  }

  @Test("MSF A/B display offset starts close and shift history at the quantized phase boundary")
  func displayOffsetHistory() {
    var scan = MSFScan()
    scan.receiveSignalChange(.falling, at: 125_000)
    for index in 0..<6 {
      emitDisplayPair(displayPairs[index], into: &scan, at: 1_025_000 + UInt64(index) * 1_000_000)
    }
    let before = scan.displaySnapshot(at: 7_020_000)
    #expect(displaySlots(before) == [.absent] + displayPairs.prefix(5).map { .decoded(.bits($0)) })
    #expect(before.secondPhaseBin == 9)
    scan.receiveSignalChange(.rising, at: 7_025_000)
    // The new edge closes the previous second, but 7.02 s still precedes the grid boundary.
    #expect(displaySlots(scan.displaySnapshot(at: 7_039_999)) == displaySlots(before))
    let after = scan.displaySnapshot(at: 7_040_000)
    #expect(displaySlots(after) == displayPairs.map { .decoded(.bits($0)) })
    #expect(after.secondPhaseBin == 0)
  }

  @Test("MSF A/B display partial history is right-aligned and retains the opening marker")
  func displayPartialHistory() {
    var scan = MSFScan()
    scan.receiveSignalChange(.falling, at: 100_000)
    scan.receiveSignalChange(.rising, at: 1_000_000)
    scan.receiveSignalChange(.falling, at: 1_500_000)
    #expect(displaySlots(scan.displaySnapshot(at: 1_600_000)) == Array(repeating: .absent, count: 6))
    emitDisplayPair(displayPairs[0], into: &scan, at: 2_000_000)
    #expect(
      displaySlots(scan.displaySnapshot(at: 2_600_000)) == [
        .absent, .absent, .absent, .absent, .absent, .decoded(.minuteMarker),
      ])
    scan.receiveSignalChange(.rising, at: 3_000_000)
    #expect(
      displaySlots(scan.displaySnapshot(at: 3_000_000)) == [
        .absent, .absent, .absent, .absent, .decoded(.minuteMarker), .decoded(.bits(displayPairs[0])),
      ])
  }

  @Test("MSF A/B display missing starts, damaged seconds and markers have distinct representations")
  func displayGapsDamageAndMarker() {
    var scan = MSFScan()
    scan.receiveSignalChange(.falling, at: 100_000)
    emitDisplayPair(displayPairs[0], into: &scan, at: 1_000_000)
    emitDisplayPair(displayPairs[1], into: &scan, at: 4_000_000)
    scan.receiveSignalChange(.rising, at: 5_000_000)
    scan.receiveSignalChange(.falling, at: 5_138_438)
    scan.receiveSignalChange(.rising, at: 6_000_000)
    scan.receiveSignalChange(.falling, at: 6_500_000)
    scan.receiveSignalChange(.rising, at: 7_000_000)
    #expect(
      displaySlots(scan.displaySnapshot(at: 7_000_000)) == [
        .decoded(.bits(displayPairs[0])), .absent, .absent,
        .decoded(.bits(displayPairs[1])), .unknown, .decoded(.minuteMarker),
      ])
    #expect(scan.recordedCount == 6)
    #expect(scan.recordedSecond(at: 1) == nil && scan.recordedSecond(at: 2) == nil)
    #expect(scan.recordedSecond(at: 4) == nil && scan.recordedSecond(at: 5) == .minuteMarker)
  }

  @Test(
    "MSF A/B display incomplete observed seconds become unknown without partial channel values",
    arguments: [0, 1, 2, 3])
  func displayIncompleteSeconds(_ scenario: Int) {
    var scan = MSFScan()
    scan.receiveSignalChange(.falling, at: 100_000)
    scan.receiveSignalChange(.rising, at: 1_000_000)
    if scenario == 1 || scenario == 2 {
      scan.receiveSignalChange(.falling, at: 1_100_000)
      scan.receiveSignalChange(.rising, at: 1_200_000)
      if scenario == 2 { scan.receiveSignalChange(.falling, at: 1_222_000) }
    } else if scenario == 3 {
      scan.receiveSignalChange(.falling, at: 1_138_000)
    }
    #expect(displaySlots(scan.displaySnapshot(at: 1_900_000)) == Array(repeating: .absent, count: 6))
    scan.receiveSignalChange(.rising, at: 2_000_000)
    #expect(
      displaySlots(scan.displaySnapshot(at: 2_000_000)) == [
        .absent, .absent, .absent, .absent, .absent, .unknown,
      ])
    #expect(scan.recordedCount == 1 && scan.recordedSecond(at: 0) == nil)
  }

  @Test(
    "MSF A/B display phase recovery retains physical positions at both tolerance limits",
    arguments: [Int64(-40_000), 0, 40_000])
  func displayPhaseRecovery(_ error: Int64) {
    var scan = MSFScan()
    scan.receiveSignalChange(.falling, at: 100_000)
    emitDisplayPair(displayPairs[0], into: &scan, at: 1_000_000)
    let recovered = UInt64(4_000_000 + error)
    emitDisplayPair(displayPairs[1], into: &scan, at: recovered)
    scan.receiveSignalChange(.rising, at: recovered + 1_000_000)
    let snapshot = scan.displaySnapshot(at: 5_040_000)
    #expect(
      displaySlots(snapshot) == [
        .absent, .absent, .decoded(.bits(displayPairs[0])),
        .absent, .absent, .decoded(.bits(displayPairs[1])),
      ])
    #expect(snapshot.secondPhaseBin == 0)
    #expect(scan.recordedCount == 4 && scan.recordedSecond(at: 3) == .bits(displayPairs[1]))
  }

  @Test(
    "MSF A/B display metadata rolls over independently of the hundred-entry scanner history",
    arguments: [12, 120])
  func displayHistoryRollover(_ count: Int) {
    var scan = MSFScan()
    scan.receiveSignalChange(.falling, at: 100_000)
    for index in 0..<count {
      emitDisplayPair(displayPairs[index % 6], into: &scan, at: UInt64(index + 1) * 1_000_000)
    }
    let now = UInt64(count + 1) * 1_000_000
    scan.receiveSignalChange(.rising, at: now)
    let snapshot = scan.displaySnapshot(at: now)
    #expect(displaySlots(snapshot) == displayPairs.map { .decoded(.bits($0)) })
    #expect(scan.recordedCount == min(count, 100))
    for index in 0..<6 {
      #expect(scan.recordedSecond(at: scan.recordedCount - 6 + index) == .bits(displayPairs[index]))
    }
    #expect(displaySlots(scan.displaySnapshot(at: now + 6_000_000)) == Array(repeating: .absent, count: 6))
  }

  @Test(
    "MSF A/B display ages slots without inventing unknown observations",
    arguments: [
      (UInt64(7_999_999), 6), (8_000_000, 5), (12_999_999, 1), (13_000_000, 0),
    ])
  func displaySlotAging(_ now: UInt64, _ remaining: Int) {
    var scan = displaySixPairs()
    let expected =
      displayPairs.suffix(remaining).map { MSFDisplaySecond.decoded(.bits($0)) }
      + Array(repeating: MSFDisplaySecond.absent, count: 6 - remaining)
    #expect(displaySlots(scan.displaySnapshot(at: now)) == expected)
    #expect(scan.recordedCount == 6)
  }

  @Test("MSF A/B display backward edges clear old metadata and subsequent acquisition uses a new anchor")
  func displayBackwardResetAndReacquisition() {
    var scan = displaySixPairs()
    scan.receiveSignalChange(.falling, at: 100_000)
    let reset = scan.displaySnapshot(at: 200_000)
    #expect(displaySlots(reset) == Array(repeating: .absent, count: 6))
    #expect(reset.secondPhaseBin == nil && scan.recordedCount == 0)
    emitDisplayPair(displayPairs[1], into: &scan, at: 1_025_000)
    scan.receiveSignalChange(.rising, at: 2_025_000)
    let acquired = scan.displaySnapshot(at: 2_040_000)
    #expect(acquired.secondPhaseBin == 0)
    #expect(
      displaySlots(acquired) == [
        .absent, .absent, .absent, .absent, .absent,
        .decoded(.bits(displayPairs[1])),
      ])
  }

  @Test("MSF display decoder reset clears A/B metadata while preserving monotonic raw activity")
  func displayDecoderResetPreservesRaw() {
    var scan = MSFScan()
    scan.receiveSignalChange(.falling, at: 100_000)
    emitDisplayPair(displayPairs[0], into: &scan, at: 1_000_000)
    // Beyond the six-step coast limit; this falling edge cannot reacquire.
    scan.receiveSignalChange(.falling, at: 7_100_000)
    let reset = scan.displaySnapshot(at: 7_120_000)
    #expect(reset.secondPhaseBin == nil && scan.recordedCount == 0)
    #expect(displaySlots(reset) == Array(repeating: .absent, count: 6))
    #expect(reset.highBins == 1 && reset.lowBins == 0x0fff_ffff_ffff_ffff)
    emitDisplayPair(displayPairs[0], into: &scan, at: 8_000_000)
    scan.receiveSignalChange(.rising, at: 9_000_000)
    #expect(
      displaySlots(scan.displaySnapshot(at: 9_000_000)) == [
        .absent, .absent, .absent, .absent, .absent, .decoded(.bits(displayPairs[0])),
      ])
  }

  @Test(
    "MSF A/B display reads before the phase anchor have no slots and do not alter later history",
    arguments: [UInt64(0), 999_999, 1_000_000])
  func displayBeforeAnchor(_ now: UInt64) {
    var scan = displaySixPairs()
    let snapshot = scan.displaySnapshot(at: now)
    #expect(displaySlots(snapshot) == Array(repeating: .absent, count: 6))
    #expect(snapshot.secondPhaseBin == (now == 1_000_000 ? 0 : nil))
    #expect(displaySlots(scan.displaySnapshot(at: 7_000_000)) == displayPairs.map { .decoded(.bits($0)) })
  }

  @Test("MSF A/B display partial closing markers wait for completion and the next start")
  func displayNearMinuteMarker() {
    var scan = MSFScan()
    scan.receiveSignalChange(.falling, at: 100_000)
    emitDisplayPair(displayPairs[0], into: &scan, at: 1_000_000)
    scan.receiveSignalChange(.rising, at: 2_000_000)
    #expect(displaySlots(scan.displaySnapshot(at: 2_480_000)).last == .decoded(.bits(displayPairs[0])))
    scan.receiveSignalChange(.falling, at: 2_500_000)
    #expect(scan.recordedSecond(at: 1) == .minuteMarker)
    #expect(displaySlots(scan.displaySnapshot(at: 2_980_000)).last == .decoded(.bits(displayPairs[0])))
    scan.receiveSignalChange(.rising, at: 3_000_000)
    #expect(
      displaySlots(scan.displaySnapshot(at: 3_000_000)).suffix(2) == [
        .decoded(.bits(displayPairs[0])), .decoded(.minuteMarker),
      ])
  }

  @Test("MSF A/B display construction does not consume decoder observations or host outputs")
  func displayNonconsumingHistory() {
    var scan = displaySixPairs()
    let original = scan.displaySnapshot(at: 7_000_000)
    let diagnostics = MSFScannerHostOutputs.diagnostics
    let frameCount = MSFScannerHostOutputs.frames.count
    _ = scan.displaySnapshot(at: 19_000_000)
    let again = scan.displaySnapshot(at: 7_000_000)
    #expect(displaySlots(original) == displayPairs.map { .decoded(.bits($0)) })
    #expect(displaySlots(again) == displaySlots(original))
    #expect(scan.recordedCount == 6)
    #expect(MSFScannerHostOutputs.diagnostics == diagnostics)
    #expect(MSFScannerHostOutputs.frames.count == frameCount)
    emitDisplayPair(displayPairs[0], into: &scan, at: 8_000_000)
    scan.receiveSignalChange(.rising, at: 9_000_000)
    #expect(scan.recordedCount == 8)
    #expect(displaySlots(original) == displayPairs.map { .decoded(.bits($0)) })
  }
}

private func displaySlots(_ snapshot: MSFDisplaySnapshot) -> [MSFDisplaySecond] {
  (0..<6).map { snapshot.seconds[$0] }
}

private func emitDisplayPair(_ pair: MSFBits, into scan: inout MSFScan, at start: UInt64) {
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

private func displaySixPairs() -> MSFScan {
  var scan = MSFScan()
  scan.receiveSignalChange(.falling, at: 100_000)
  for index in 0..<6 {
    emitDisplayPair(displayPairs[index], into: &scan, at: UInt64(index + 1) * 1_000_000)
  }
  scan.receiveSignalChange(.rising, at: 7_000_000)
  return scan
}

extension MSFScanTests {
  @Test("Validated marker timing reaches the display before calendar acquisition at full sample precision")
  func displayMarkerTimingBeforeCalendar() {
    var scan = MSFScan()
    scan.receiveSignalChange(.falling, at: 100_000)
    scan.receiveSignalChange(.rising, at: 1_000_000)
    let before = scan.displaySnapshot(at: 1_499_999)
    #expect(before.minuteMarkerTime == nil)
    #expect(before.secondPhaseBin != nil)
    #expect(!MSFDisplaySnapshot(raw: before, clockSnapshot: .unknown).clockSnapshot.hasSecondTiming)
    scan.receiveSignalChange(.falling, at: 1_500_000)
    #expect(MSFScannerHostOutputs.frames.isEmpty)
    for now: UInt64 in [1_512_345, 1_516_666, 60_999_999, 61_000_000, 61_123_456] {
      let raw = scan.displaySnapshot(at: now)
      let merged = MSFDisplaySnapshot(raw: raw, clockSnapshot: .unknown)
      #expect(raw.timestamp == now - now % 20_000 && raw.sampleTime == now)
      #expect(raw.minuteMarkerTime == 1_000_000 && merged.minuteMarkerTime == raw.minuteMarkerTime)
      #expect(merged.sampleTime == now)
      let clock = merged.clockSnapshot
      #expect(clock.hasSecondTiming)
      #expect(clock.calendarDateTime.second == Int(((now - 1_000_000) % 60_000_000) / 1_000_000))
      #expect(clock.subsecondMicroseconds == UInt32((now - 1_000_000) % 1_000_000))
      #expect(clock.clockState.hour == .unknown && clock.clockState.minute == .unknown)
    }
    // An actual scanner reset drops its marker-derived timing; no display anchor
    // survives separately from the existing scanner/model/acquisition state.
    scan.receiveSignalChange(.falling, at: 8_000_000)
    let reset = scan.displaySnapshot(at: 8_000_000)
    #expect(reset.minuteMarkerTime == nil)
    #expect(!MSFDisplaySnapshot(raw: reset, clockSnapshot: .unknown).clockSnapshot.hasSecondTiming)
  }
}

@Test("Raw marker timing cannot replace authoritative clock timing or underflow before its anchor")
func displayMarkerClockPrecedence() {
  let clock = ClockSnapshot.unknown.withSecondTiming(at: 20_123_456, minuteMarkerTime: 10_000_000)
  let raw = MSFDisplaySnapshot(
    clockSnapshot: .unknown, secondPhaseBin: 0, timestamp: 20_000_000,
    signalHigh: true, highBins: 0, lowBins: 0, sampleTime: 20_123_456, minuteMarkerTime: 19_000_000)
  let merged = MSFDisplaySnapshot(raw: raw, clockSnapshot: clock)
  #expect(merged.clockSnapshot.hasSecondTiming)
  #expect(merged.clockSnapshot.calendarDateTime.second == 10)
  #expect(merged.clockSnapshot.subsecondMicroseconds == 123_456)
  #expect(!ClockSnapshot.unknown.hasSecondTiming)
  #expect(!ClockSnapshot.unknown.withSecondTiming(at: 0, minuteMarkerTime: 1).hasSecondTiming)
}
