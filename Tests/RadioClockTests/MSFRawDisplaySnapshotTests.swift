//
//  MSFRawDisplaySnapshotTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

private let rawAllBins: UInt64 = 0x0fff_ffff_ffff_ffff
private let rawNewestBin: UInt64 = 0x0800_0000_0000_0000

// observeRawSignal does not call the shared host output recorder. These tests
// can run concurrently; edge-driven tests below extend the serialized suite.
@Test(
  "MSF raw display starts blank at timestamp boundaries",
  arguments: [UInt64(0), 19_999, 20_000, 99_999, 100_000, 6_000_000, UInt64.max])
func rawDisplayEmpty(_ now: UInt64) {
  var scan = MSFScan()
  let snapshot = scan.displaySnapshot(at: now)
  #expect(snapshot.timestamp == now - now % 20_000)
  #expect(snapshot.highBins == 0 && snapshot.lowBins == 0)
  #expect(!snapshot.signalHigh && snapshot.secondPhaseBin == nil)
  #expect((0..<6).allSatisfy { snapshot.seconds[$0] == .absent })
}

@Test(
  "MSF raw display carries a steady known level across six seconds of empty intervals",
  arguments: [false, true])
func rawDisplaySteadyLevel(_ high: Bool) {
  var scan = MSFScan()
  scan.observeRawSignal(high: high, at: 0)
  for now: UInt64 in [6_000_000, 12_000_000, 60_000_000] {
    let snapshot = scan.displaySnapshot(at: now)
    #expect(snapshot.highBins == (high ? rawAllBins : 0))
    #expect(snapshot.lowBins == (high ? 0 : rawAllBins))
    #expect(snapshot.signalHigh == high)
    #expect(snapshot.secondPhaseBin == nil && scan.recordedCount == 0)
  }
}

@Test(
  "MSF raw display quantizes the trace to completed twenty-millisecond samples",
  arguments: [
    (UInt64(0), UInt64(0), UInt64(0)), (19_999, 0, 0),
    (20_000, 20_000, rawNewestBin), (39_999, 20_000, rawNewestBin),
    (40_000, 40_000, rawNewestBin), (99_999, 80_000, rawNewestBin),
    (100_000, 100_000, rawNewestBin),
  ])
func rawDisplayQuantization(_ now: UInt64, _ timestamp: UInt64, _ highBins: UInt64) {
  var scan = MSFScan()
  scan.observeRawSignal(high: true, at: 1)
  let snapshot = scan.displaySnapshot(at: now)
  #expect(snapshot.timestamp == timestamp && snapshot.highBins == highBins)
  #expect(snapshot.lowBins == 0 && snapshot.signalHigh)
}

@Test(
  "MSF raw display unknown starting levels leave earlier history blank",
  arguments: [false, true])
func rawDisplayUnknownStart(_ high: Bool) {
  var scan = MSFScan()
  scan.observeRawSignal(high: high, at: 5_905_000)
  let incomplete = scan.displaySnapshot(at: 5_919_999)
  #expect(incomplete.highBins == 0 && incomplete.lowBins == 0)
  #expect(incomplete.signalHigh == high)
  let completed = scan.displaySnapshot(at: 6_000_000)
  #expect(completed.highBins == (high ? rawNewestBin : 0))
  #expect(completed.lowBins == (high ? 0 : rawNewestBin))
}

@Test(
  "MSF raw display first-interval transitions record both flags without inventing earlier levels",
  arguments: [false, true])
func rawDisplayUnknownStartTransitions(_ firstHigh: Bool) {
  var scan = MSFScan()
  scan.observeRawSignal(high: firstHigh, at: 5_905_000)
  scan.observeRawSignal(high: !firstHigh, at: 5_905_001)
  let partial = scan.displaySnapshot(at: 5_919_999)
  #expect(partial.highBins == 0 && partial.lowBins == 0)
  let completed = scan.displaySnapshot(at: 6_000_000)
  #expect(completed.highBins == rawNewestBin && completed.lowBins == rawNewestBin)
  #expect(completed.signalHigh == !firstHigh)
}

@Test(
  "MSF raw display LOW and HIGH flags coexist after transitions in one interval",
  arguments: [false, true], [UInt64(5_905_000), 5_905_001])
func rawDisplayIndependentLevelFlags(_ initialHigh: Bool, _ finalTime: UInt64) {
  var scan = MSFScan()
  scan.observeRawSignal(high: initialHigh, at: 0)
  scan.observeRawSignal(high: !initialHigh, at: 5_905_000)
  scan.observeRawSignal(high: initialHigh, at: finalTime)
  let snapshot = scan.displaySnapshot(at: 6_000_000)
  #expect(snapshot.highBins == (initialHigh ? rawAllBins : rawNewestBin))
  #expect(snapshot.lowBins == (initialHigh ? rawNewestBin : rawAllBins))
  #expect(snapshot.signalHigh == initialHigh)
}

@Test(
  "MSF raw display excludes partial activity and restores its known starting level",
  arguments: [false, true])
func rawDisplayKnownPartialStart(_ initialHigh: Bool) {
  var scan = MSFScan()
  scan.observeRawSignal(high: initialHigh, at: 0)
  scan.observeRawSignal(high: !initialHigh, at: 6_003_000)
  let partial = scan.displaySnapshot(at: 6_019_999)
  #expect(partial.timestamp == 6_000_000 && partial.signalHigh == !initialHigh)
  #expect(partial.highBins == (initialHigh ? rawAllBins : 0))
  #expect(partial.lowBins == (initialHigh ? 0 : rawAllBins))
  let completed = scan.displaySnapshot(at: 6_020_000)
  #expect(completed.highBins == (initialHigh ? rawAllBins : rawNewestBin))
  #expect(completed.lowBins == (initialHigh ? rawNewestBin : rawAllBins))
}

@Test(
  "MSF raw display includes transitions on the correct side of a sampling boundary",
  arguments: [
    (UInt64(19_999), true), (20_000, false), (20_001, false),
  ])
func rawDisplaySampleBoundary(_ transition: UInt64, _ visibleAtBoundary: Bool) {
  var scan = MSFScan()
  scan.observeRawSignal(high: false, at: 0)
  scan.observeRawSignal(high: true, at: transition)
  let first = scan.displaySnapshot(at: 20_000)
  #expect(first.highBins == (visibleAtBoundary ? rawNewestBin : 0))
  #expect(first.lowBins == rawNewestBin && first.signalHigh)
  let second = scan.displaySnapshot(at: 40_000)
  #expect(second.highBins == rawNewestBin && second.lowBins == rawNewestBin)
}

@Test(
  "MSF raw display groups five completed samples into each hundred-millisecond bin",
  arguments: [
    (UInt64(1), UInt64(0x0400_0000_0000_0000)),
    (79_999, 0x0400_0000_0000_0000), (80_000, 0x0400_0000_0000_0000),
    (99_999, 0x0c00_0000_0000_0000), (100_000, 0x0800_0000_0000_0000),
  ])
func rawDisplayBinBoundary(_ pulseTime: UInt64, _ expectedHigh: UInt64) {
  var scan = MSFScan()
  scan.observeRawSignal(high: false, at: 0)
  scan.observeRawSignal(high: true, at: pulseTime)
  scan.observeRawSignal(high: false, at: pulseTime + 1)
  // At 200 ms, samples 0...4 belong to bin 58 and 5...9 to bin 59.
  let snapshot = scan.displaySnapshot(at: 200_000)
  #expect(snapshot.highBins == expectedHigh)
  #expect(snapshot.lowBins == 0x0c00_0000_0000_0000)
}

@Test(
  "MSF raw display pulse scrolling has explicit six-second window boundaries",
  arguments: [
    (UInt64(6_000_000), UInt64(0x0800_0000_0000_0000)),
    (6_019_999, 0x0800_0000_0000_0000), (6_020_000, 0x0400_0000_0000_0000),
    (6_099_999, 0x0400_0000_0000_0000), (6_100_000, 0x0400_0000_0000_0000),
    (11_800_000, 2), (11_900_000, 1), (11_919_999, 1),
    (11_920_000, 0), (12_100_000, 0),
  ])
func rawDisplayPulseScrolling(_ now: UInt64, _ highBins: UInt64) {
  var scan = MSFScan()
  scan.observeRawSignal(high: false, at: 0)
  scan.observeRawSignal(high: true, at: 5_905_000)
  scan.observeRawSignal(high: false, at: 5_905_001)
  let snapshot = scan.displaySnapshot(at: now)
  #expect(snapshot.highBins == highBins && snapshot.lowBins == rawAllBins)
}

@Test(
  "MSF raw display partial history does not extend before the first observation",
  arguments: [
    (UInt64(0), UInt64(0)), (20_000, rawNewestBin),
    (100_000, rawNewestBin), (120_000, UInt64(0x0c00_0000_0000_0000)),
    (200_000, 0x0c00_0000_0000_0000),
  ])
func rawDisplayPartialHistory(_ now: UInt64, _ expected: UInt64) {
  var scan = MSFScan()
  scan.observeRawSignal(high: false, at: 0)
  let snapshot = scan.displaySnapshot(at: now)
  #expect(snapshot.highBins == 0 && snapshot.lowBins == expected)
}

@Test(
  "MSF raw display repeated same-level observations do not manufacture opposite activity",
  arguments: [false, true])
func rawDisplayRepeatedLevels(_ high: Bool) {
  var scan = MSFScan()
  for now: UInt64 in [0, 0, 1, 19_999, 20_000, 20_000, 99_999, 6_000_000] {
    scan.observeRawSignal(high: high, at: now)
  }
  let snapshot = scan.displaySnapshot(at: 6_020_000)
  #expect(snapshot.highBins == (high ? rawAllBins : 0))
  #expect(snapshot.lowBins == (high ? 0 : rawAllBins))
  #expect(scan.recordedCount == 0)
}

@Test("MSF raw display coalesces dense transitions without losing either level")
func rawDisplayDenseActivity() {
  var scan = MSFScan()
  scan.observeRawSignal(high: false, at: 0)
  for tick in 0..<600 {
    for edge in 0..<40 {
      scan.observeRawSignal(
        high: edge % 2 == 0,
        at: UInt64(tick) * 10_000 + UInt64(edge) * 200 + 1)
    }
  }
  let snapshot = scan.displaySnapshot(at: 6_000_000)
  #expect(snapshot.highBins == rawAllBins && snapshot.lowBins == rawAllBins)
  #expect(!snapshot.signalHigh && scan.recordedCount == 0)
}

@Test("MSF raw display ring reuse rejects activity from an earlier interval")
func rawDisplayRingReuse() {
  var scan = MSFScan()
  scan.observeRawSignal(high: false, at: 0)
  scan.observeRawSignal(high: true, at: 1)
  scan.observeRawSignal(high: false, at: 2)
  #expect(scan.displaySnapshot(at: 20_000).highBins == rawNewestBin)
  // 301 samples later, sample slot zero now holds only LOW observations.
  scan.observeRawSignal(high: false, at: 6_020_000)
  let snapshot = scan.displaySnapshot(at: 6_040_000)
  #expect(snapshot.highBins == 0 && snapshot.lowBins == rawAllBins)
  #expect(scan.displaySnapshot(at: 12_060_000).highBins == 0)
}

@Test("MSF raw display retains the oldest completed sample alongside the current partial sample")
func rawDisplayRingPartialCapacity() {
  var scan = MSFScan()
  scan.observeRawSignal(high: true, at: 0)
  scan.observeRawSignal(high: false, at: 1)
  scan.observeRawSignal(high: true, at: 6_003_000)
  let partial = scan.displaySnapshot(at: 6_019_999)
  #expect(partial.highBins == 1 && partial.lowBins == rawAllBins && partial.signalHigh)
  let next = scan.displaySnapshot(at: 6_020_000)
  #expect(next.highBins == rawNewestBin && next.lowBins == rawAllBins)
}

@Test("MSF raw display sparse stale tags cannot resurrect an old pulse")
func rawDisplayStaleSample() {
  var scan = MSFScan()
  scan.observeRawSignal(high: false, at: 0)
  scan.observeRawSignal(high: true, at: 5_905_000)
  scan.observeRawSignal(high: false, at: 5_905_001)
  for now: UInt64 in [12_020_000, 18_040_000, 60_000_000] {
    let snapshot = scan.displaySnapshot(at: now)
    #expect(snapshot.highBins == 0 && snapshot.lowBins == rawAllBins)
  }
}

@Test(
  "MSF raw display backward observations discard the previous timebase",
  arguments: [false, true])
func rawDisplayBackwardObservation(_ high: Bool) {
  var scan = MSFScan()
  scan.observeRawSignal(high: !high, at: 0)
  scan.observeRawSignal(high: !high, at: 12_000_000)
  scan.observeRawSignal(high: high, at: 10_000)
  let snapshot = scan.displaySnapshot(at: 20_000)
  #expect(snapshot.highBins == (high ? rawNewestBin : 0))
  #expect(snapshot.lowBins == (high ? 0 : rawNewestBin))
  #expect(snapshot.signalHigh == high)
}

@Test(
  "MSF raw display accepts unsigned timestamp extremes without wrapping sample tags",
  arguments: [false, true])
func rawDisplayMaximumTimestamp(_ high: Bool) {
  var scan = MSFScan()
  scan.observeRawSignal(high: high, at: UInt64.max - 20_000)
  let snapshot = scan.displaySnapshot(at: UInt64.max)
  #expect(snapshot.timestamp == UInt64.max - 11_615)
  #expect(snapshot.highBins == (high ? rawNewestBin : 0))
  #expect(snapshot.lowBins == (high ? 0 : rawNewestBin))
  #expect(snapshot.signalHigh == high)
}

@Test("MSF raw display reads do not consume history or alter captured snapshot values")
func rawDisplayNonconsumingReads() {
  var scan = MSFScan()
  scan.observeRawSignal(high: false, at: 0)
  scan.observeRawSignal(high: true, at: 5_905_000)
  scan.observeRawSignal(high: false, at: 5_905_001)
  let original = scan.displaySnapshot(at: 6_000_000)
  _ = scan.displaySnapshot(at: 12_100_000)
  let reread = scan.displaySnapshot(at: 6_000_000)
  #expect(reread.highBins == rawNewestBin && reread.lowBins == rawAllBins)
  #expect(original.highBins == rawNewestBin && original.timestamp == 6_000_000)
  #expect(scan.recordedCount == 0)
}

extension MSFScanTests {
  @Test("MSF raw display coalesces IRQ and physical-level observations without synthetic seconds")
  func rawDisplayLatchedLevels() {
    var scan = MSFScan()
    scan.observeRawSignal(high: false, at: 0)
    scan.receiveSignalChange(.rising, at: 5_905_000)
    scan.observeRawSignal(high: false, at: 5_905_000)
    scan.observeRawSignal(high: true, at: 5_905_000)
    let snapshot = scan.displaySnapshot(at: 6_000_000)
    #expect(snapshot.highBins == rawNewestBin && snapshot.lowBins == rawAllBins)
    #expect(snapshot.signalHigh && scan.recordedCount == 0)
    #expect(MSFScannerHostOutputs.diagnostics.count == 1)
  }

  @Test("MSF raw display preserves twenty-four thousand undecodable edges and wraps its ring")
  func rawDisplayDenseEdgesAndRollover() {
    var scan = MSFScan()
    scan.observeRawSignal(high: false, at: 0)
    for tick in 0..<600 {
      for edge in 0..<40 {
        scan.receiveSignalChange(
          edge % 2 == 0 ? .rising : .falling,
          at: UInt64(tick) * 10_000 + UInt64(edge) * 200 + 1)
      }
    }
    let noise = scan.displaySnapshot(at: 6_000_000)
    #expect(noise.highBins == rawAllBins && noise.lowBins == rawAllBins)
    #expect(scan.recordedCount == 0 && noise.secondPhaseBin == nil)
    scan.receiveSignalChange(.rising, at: 6_003_000)
    #expect(scan.displaySnapshot(at: 6_004_000).signalHigh)
    scan.receiveSignalChange(.falling, at: 6_005_000)
    for tick in 601..<1200 {
      scan.receiveSignalChange(.falling, at: UInt64(tick) * 10_000)
    }
    let wrapped = scan.displaySnapshot(at: 12_000_000)
    #expect(wrapped.highBins == 1 && wrapped.lowBins == rawAllBins)
    #expect(scan.displaySnapshot(at: 12_100_000).highBins == 0)
    scan.receiveSignalChange(.rising, at: 10_000)
    let reset = scan.displaySnapshot(at: 20_000)
    #expect(reset.highBins == rawNewestBin && reset.lowBins == 0)
  }
}
