//
//  MSFScanTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

// Only this serialized suite uses the host output boundary. Each case gets a
// new suite instance and clears capture before feeding edges to a local scanner.
@Suite("MSF scanner", .serialized)
struct MSFScanTests {
  init() {
    MSFScannerHostOutputs.reset()
  }

  @Test(
    "MSF scanner interprets physical pulse edges for all A/B pairs under either polarity",
    arguments: [MSFScan.Polarity.carrierPresentLow, .carrierPresentHigh],
    [
      MSFBits(a: false, b: false), MSFBits(a: false, b: true),
      MSFBits(a: true, b: false), MSFBits(a: true, b: true),
    ])
  func polarityPairRecognition(_ polarity: MSFScan.Polarity, _ pair: MSFBits) throws {
    var scan = scanAtFirstRise(polarity: polarity)
    let boundary = try #require(MSFScannerHostOutputs.diagnostics.last)
    #expect(boundary.rising == (polarity == .carrierPresentLow))
    emitPulseBody(pair, into: &scan, afterRiseAt: 1_000_000, polarity: polarity)
    #expect(scan.recordedCount == (!pair.a && !pair.b ? 0 : 1))
    let pulseEnd = try #require(MSFScannerHostOutputs.diagnostics.last)
    #expect(pulseEnd.rising == (polarity == .carrierPresentHigh))
    #expect(pulseEnd.state == (!pair.a && pair.b ? 3 : 1))
    receiveFixtureEdge(.rising, into: &scan, at: 2_000_000, polarity: polarity)
    #expect(scanHistory(scan) == [.bits(pair)])
    #expect(MSFScannerHostOutputs.diagnostics.allSatisfy { $0.resetReason == 0 })
  }

  @Test(
    "MSF scanner publishes and decodes fixed complete frames under either polarity",
    arguments: [MSFScan.Polarity.carrierPresentLow, .carrierPresentHigh], [58, 59, 60])
  func polarityCompletedFrames(_ polarity: MSFScan.Polarity, _ count: Int) throws {
    let (scan, frame) = try publishedFixtureFrame(dataCount: count, polarity: polarity)
    #expect(scan.recordedSecond(at: 0) == .minuteMarker)
    #expect(scan.recordedSecond(at: count + 1) == .minuteMarker)
    #expect(frame.dataCount == count && frame.hasOpeningMarker && frame.unknownBits == 0)
    #expect(frame.aBits & 0x7ff_ffff_ffff == scannerFixtureA)
    #expect(frame.bBits & 0x7ff_ffff_ffff == scannerFixtureB)
    #expect(frame.closingMarkerTime == 2_000_000 + UInt64(count) * 1_000_000)
    expectScannerFixtureDecoded(frame)
  }

  @Test(
    "MSF scanner inverted input preserves decoding and recovery while swapping raw GPIO history",
    arguments: [0, 1, 2])
  func polarityInversion(_ scenario: Int) throws {
    let damaged: Set<Int> = scenario == 1 ? [30] : []
    let missing: Set<Int> = scenario == 2 ? [30] : []
    var (low, lowFrame) = try publishedFixtureFrame(
      damaged: damaged, missing: missing, completedPrefix: true,
      polarity: .carrierPresentLow)
    let lowDiagnostics = MSFScannerHostOutputs.diagnostics
    MSFScannerHostOutputs.reset()
    var (high, highFrame) = try publishedFixtureFrame(
      damaged: damaged, missing: missing, completedPrefix: true,
      polarity: .carrierPresentHigh)
    let highDiagnostics = MSFScannerHostOutputs.diagnostics
    #expect(scanHistory(low) == scanHistory(high))
    #expect(highFrame.aBits == lowFrame.aBits && highFrame.bBits == lowFrame.bBits)
    #expect(highFrame.unknownBits == lowFrame.unknownBits)
    #expect(highFrame.dataCount == lowFrame.dataCount)
    #expect(highFrame.hasOpeningMarker == lowFrame.hasOpeningMarker)
    #expect(highFrame.closingMarkerTime == lowFrame.closingMarkerTime)
    #expect(highFrame.decode().decodeStatus == (scenario == 0 ? .valid : .missingData))
    #expect(lowDiagnostics.count == highDiagnostics.count)
    for (lowRecord, highRecord) in zip(lowDiagnostics, highDiagnostics) {
      #expect(lowRecord.rising != highRecord.rising)
      #expect(lowRecord.state == highRecord.state)
      #expect(lowRecord.sincePrevious == highRecord.sincePrevious)
      #expect(lowRecord.sinceSecond == highRecord.sinceSecond)
      #expect(lowRecord.scanIndex == highRecord.scanIndex)
      #expect(lowRecord.resetReason == highRecord.resetReason)
      #expect(lowRecord.event == highRecord.event)
      #expect(lowRecord.phaseStep == highRecord.phaseStep)
      #expect(lowRecord.missingSlots == highRecord.missingSlots)
      #expect(lowRecord.phaseError == highRecord.phaseError)
    }
    let lowSnapshot = low.displaySnapshot(at: 61_520_000)
    let highSnapshot = high.displaySnapshot(at: 61_520_000)
    #expect(lowSnapshot.highBins != lowSnapshot.lowBins)
    #expect(highSnapshot.highBins == lowSnapshot.lowBins)
    #expect(highSnapshot.lowBins == lowSnapshot.highBins)
    #expect(highSnapshot.signalHigh != lowSnapshot.signalHigh)
    #expect(highSnapshot.timestamp == lowSnapshot.timestamp)
    #expect(highSnapshot.secondPhaseBin == lowSnapshot.secondPhaseBin)
    for index in 0..<6 {
      #expect(highSnapshot.seconds[index] == lowSnapshot.seconds[index])
    }
  }

  @Test(
    "MSF scanner initial raw level does not invent decoder edges under either polarity",
    arguments: [MSFScan.Polarity.carrierPresentLow, .carrierPresentHigh], [false, true])
  func polarityInitialLevel(_ polarity: MSFScan.Polarity, _ carrierPresent: Bool) {
    var scan = MSFScan(polarity: polarity)
    let initialHigh = polarity == .carrierPresentHigh ? carrierPresent : !carrierPresent
    scan.observeRawSignal(high: initialHigh, at: 0)
    let snapshot = scan.displaySnapshot(at: 100_000)
    #expect(snapshot.signalHigh == initialHigh)
    #expect(snapshot.highBins == (initialHigh ? 0x0800_0000_0000_0000 : 0))
    #expect(snapshot.lowBins == (initialHigh ? 0 : 0x0800_0000_0000_0000))
    #expect(snapshot.secondPhaseBin == nil && scan.recordedCount == 0)
    #expect(MSFScannerHostOutputs.diagnostics.isEmpty)
    if carrierPresent {
      // A pulse start without a preceding observed carrier interval cannot acquire phase.
      receiveFixtureEdge(.rising, into: &scan, at: 100_000, polarity: polarity)
      receiveFixtureEdge(.falling, into: &scan, at: 200_000, polarity: polarity)
    } else {
      receiveFixtureEdge(.falling, into: &scan, at: 100_000, polarity: polarity)
    }
    #expect(scan.recordedCount == 0 && scan.displaySnapshot(at: 300_000).secondPhaseBin == nil)
    receiveFixtureEdge(.rising, into: &scan, at: 1_000_000, polarity: polarity)
    emitPulseBody(
      MSFBits(a: true, b: false), into: &scan,
      afterRiseAt: 1_000_000, polarity: polarity)
    #expect(scanHistory(scan) == [.bits(MSFBits(a: true, b: false))])
    #expect(scan.displaySnapshot(at: 1_200_000).signalHigh == (polarity == .carrierPresentHigh))
    #expect(MSFScannerHostOutputs.frames.isEmpty)
  }

  @Test(
    "MSF scanner starts empty and rejects history indices outside its accepted entries",
    arguments: [Int.min, -1, 0, 99, 100, Int.max])
  func emptyHistory(_ index: Int) {
    let scan = MSFScan()
    #expect(scan.recordedCount == 0)
    #expect(scan.recordedSecond(at: index) == nil)
    #expect(MSFScannerHostOutputs.diagnostics.isEmpty)
    #expect(MSFScannerHostOutputs.frames.isEmpty)
  }

  @Test(
    "MSF scanner initial fall-to-rise acquisition interval is exclusive at 480 ms and inclusive at 1200 ms",
    arguments: [
      (UInt64(480_000), false), (480_001, true), (900_000, true), (1_200_000, true),
      (1_200_001, false),
    ])
  func initialAcquisition(_ interval: UInt64, _ accepted: Bool) {
    var scan = MSFScan()
    let firstRise = 100_000 + interval
    scan.receiveSignalChange(.falling, at: 100_000)
    scan.receiveSignalChange(.rising, at: firstRise)
    scan.receiveSignalChange(.falling, at: firstRise + 100_000)
    scan.receiveSignalChange(.rising, at: firstRise + 1_000_000)
    #expect(scanHistory(scan) == (accepted ? [.bits(MSFBits(a: false, b: false))] : []))
    #expect(MSFScannerHostOutputs.frames.isEmpty)
  }

  @Test(
    "MSF scanner classifies all four pairs and confirms A0 B0 only at the next boundary",
    arguments: [
      MSFBits(a: false, b: false), MSFBits(a: false, b: true),
      MSFBits(a: true, b: false), MSFBits(a: true, b: true),
    ])
  func pairRecognition(_ pair: MSFBits) {
    var scan = scanAtFirstRise()
    emitPulseBody(pair, into: &scan, afterRiseAt: 1_000_000)
    #expect(scan.recordedCount == (!pair.a && !pair.b ? 0 : 1))
    scan.receiveSignalChange(.rising, at: 2_000_000)
    #expect(scanHistory(scan) == [.bits(pair)])
    scan.receiveSignalChange(.falling, at: 2_200_000)
    #expect(scanHistory(scan) == [.bits(pair), .bits(MSFBits(a: true, b: false))])
    #expect(MSFScannerHostOutputs.diagnostics.allSatisfy { $0.resetReason == 0 })
  }

  @Test("MSF scanner requires the B falling edge before accepting A0 B1")
  func bFallRequired() {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_100_000)
    scan.receiveSignalChange(.rising, at: 1_200_000)
    #expect(scan.recordedCount == 0)
    scan.receiveSignalChange(.falling, at: 1_300_000)
    #expect(scanHistory(scan) == [.bits(MSFBits(a: false, b: true))])
  }

  @Test("MSF scanner marker recognition waits for its validated falling edge")
  func openingMarker() {
    var scan = scanAtFirstRise()
    #expect(scan.recordedCount == 0 && MSFScannerHostOutputs.frames.isEmpty)
    scan.receiveSignalChange(.falling, at: 1_500_000)
    #expect(scanHistory(scan) == [.minuteMarker])
    #expect(MSFScannerHostOutputs.frames.isEmpty)
  }

  @Test("MSF scanner publishes an empty marker-to-marker frame as insufficient data")
  func emptyMarkerFrame() throws {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_500_000)
    scan.receiveSignalChange(.rising, at: 2_000_000)
    #expect(MSFScannerHostOutputs.frames.isEmpty)
    scan.receiveSignalChange(.falling, at: 2_500_000)
    #expect(MSFScannerHostOutputs.frames.count == 1)
    let frame = try #require(MSFScannerHostOutputs.frames.first)
    #expect(frame.dataCount == 0 && frame.hasOpeningMarker)
    #expect(frame.aBits == 0 && frame.bBits == 0 && frame.unknownBits == 0)
    #expect(frame.closingMarkerTime == 2_000_000)
    #expect(frame.decode().decodeStatus == .insufficientData)
  }

  @Test("MSF scanner keeps consecutive mixed pairs and markers in observed order")
  func mixedSequence() {
    var scan = scanAtFirstRise()
    emitPulseBody(MSFBits(a: false, b: false), into: &scan, afterRiseAt: 1_000_000)
    emitSecond(MSFBits(a: false, b: true), into: &scan, at: 2_000_000)
    emitSecond(MSFBits(a: true, b: true), into: &scan, at: 3_000_000)
    scan.receiveSignalChange(.rising, at: 4_000_000)
    scan.receiveSignalChange(.falling, at: 4_500_000)
    #expect(
      scanHistory(scan) == [
        .bits(MSFBits(a: false, b: false)),
        .bits(MSFBits(a: false, b: true)), .bits(MSFBits(a: true, b: true)), .minuteMarker,
      ])
    #expect(MSFScannerHostOutputs.diagnostics.allSatisfy { $0.resetReason == 0 })
  }

  @Test(
    "MSF scanner first-fall pulse classes accept inclusive thirty-millisecond bounds",
    arguments: [UInt64(100_000), 200_000, 300_000, 500_000],
    [-30_001, -30_000, 0, 30_000, 30_001])
  func firstFallTolerance(_ nominal: UInt64, _ error: Int) throws {
    var scan = scanAtFirstRise()
    let offset = UInt64(Int(nominal) + error)
    scan.receiveSignalChange(.falling, at: 1_000_000 + offset)
    let diagnostic = try #require(MSFScannerHostOutputs.diagnostics.last)
    if error < -30_000 || error > 30_000 {
      #expect(diagnostic.event == 1)  // damaged second
      #expect(scan.recordedCount == 0)
      scan.receiveSignalChange(.rising, at: 2_000_000)
      #expect(scanHistory(scan) == [nil])
    } else {
      #expect(diagnostic.resetReason == 0)
      scan.receiveSignalChange(.rising, at: 2_000_000)
      let expected: MSFSecond =
        nominal == 500_000
        ? .minuteMarker
        : .bits(MSFBits(a: nominal != 100_000, b: nominal == 300_000))
      #expect(scanHistory(scan) == [expected])
    }
  }

  @Test(
    "MSF scanner B start and completion enforce independent inclusive pulse windows",
    arguments: [
      (true, UInt64(170_000), true), (true, 230_000, true),
      (true, 169_999, false), (true, 230_001, false),
      (false, 270_000, true), (false, 330_000, true),
      (false, 269_999, false), (false, 330_001, false),
    ])
  func bPulseTolerance(_ testingRise: Bool, _ offset: UInt64, _ accepted: Bool) {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_100_000)
    scan.receiveSignalChange(.rising, at: testingRise ? 1_000_000 + offset : 1_200_000)
    if accepted || !testingRise {
      #expect(scan.recordedCount == 0)
    }
    scan.receiveSignalChange(.falling, at: testingRise ? 1_300_000 : 1_000_000 + offset)
    scan.receiveSignalChange(.rising, at: 2_000_000)
    #expect(scanHistory(scan) == (accepted ? [.bits(MSFBits(a: false, b: true))] : [nil]))
  }

  @Test(
    "MSF scanner direct second tolerance hands neighbouring edges to phase recovery",
    arguments: [UInt64(100_000), 200_000], [970_000, 1_030_000, 969_999, 1_030_001])
  func directBoundaryTolerance(_ firstFall: UInt64, _ interval: Int) throws {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_000_000 + firstFall)
    scan.receiveSignalChange(.rising, at: 1_000_000 + UInt64(interval))
    #expect(scanHistory(scan) == [.bits(MSFBits(a: firstFall == 200_000, b: false))])
    let diagnostic = try #require(MSFScannerHostOutputs.diagnostics.last)
    #expect(diagnostic.resetReason == 0 && diagnostic.missingSlots == 0)
    if interval == 969_999 || interval == 1_030_001 {
      #expect(diagnostic.event == 4 && diagnostic.phaseStep == 1)
      #expect(diagnostic.phaseError == Int32(interval - 1_000_000))
    } else {
      #expect(diagnostic.event == 0 && diagnostic.phaseStep == 0)
    }
  }

  @Test(
    "MSF scanner accepts independent measured first-fall fixtures",
    arguments: [
      (UInt64(90_057), 0), (93_184, 0), (97_942, 0), (99_391, 0), (100_283, 0),
      (108_910, 0), (113_722, 0), (116_410, 0), (119_747, 0), (120_091, 0), (122_283, 0),
      (124_548, 0),
      (188_589, 1), (193_340, 1), (198_869, 1), (202_305, 1), (205_541, 1),
      (208_158, 1), (216_976, 1), (219_452, 1), (224_339, 1), (227_213, 1),
      (301_502, 2), (302_349, 2), (489_998, 3), (506_316, 3),
    ])
  func measuredFirstFalls(_ offset: UInt64, _ classification: Int) {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_000_000 + offset)
    scan.receiveSignalChange(.rising, at: 2_000_000)
    let expected: MSFSecond =
      classification == 3
      ? .minuteMarker
      : .bits(MSFBits(a: classification != 0, b: classification == 2))
    #expect(scanHistory(scan) == [expected])
  }

  @Test(
    "MSF scanner measured second boundaries close one pair and open the next",
    arguments: [
      UInt64(980_832), 989_358, 991_524, 998_062, 1_000_007, 1_011_596, 1_015_714, 1_021_059,
    ])
  func measuredSecondBoundaries(_ interval: UInt64) {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_200_000)
    scan.receiveSignalChange(.rising, at: 1_000_000 + interval)
    scan.receiveSignalChange(.falling, at: 1_100_000 + interval)
    #expect(scanHistory(scan) == [.bits(MSFBits(a: true, b: false))])
    #expect(MSFScannerHostOutputs.diagnostics.allSatisfy { $0.resetReason == 0 })
  }

  @Test("MSF scanner malformed first fall records damage context and one positional unknown")
  func damageDiagnostics() throws {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_200_000)
    scan.receiveSignalChange(.rising, at: 2_000_000)
    scan.receiveSignalChange(.falling, at: 2_140_000)
    let damaged = try #require(MSFScannerHostOutputs.diagnostics.last)
    #expect(!damaged.rising && damaged.event == 1 && damaged.resetReason == 0)
    #expect(damaged.sincePrevious == 140_000 && damaged.sinceSecond == 140_000)
    #expect(damaged.scanIndex == 1)
    #expect(scanHistory(scan) == [.bits(MSFBits(a: true, b: false))])
    scan.receiveSignalChange(.rising, at: 3_000_000)
    let missing = try #require(MSFScannerHostOutputs.diagnostics.last)
    #expect(missing.event == 2 && missing.missingSlots == 1 && missing.phaseStep == 0)
    emitPulseBody(MSFBits(a: false, b: false), into: &scan, afterRiseAt: 3_000_000)
    scan.receiveSignalChange(.rising, at: 4_000_000)
    #expect(
      scanHistory(scan) == [
        .bits(MSFBits(a: true, b: false)), nil, .bits(MSFBits(a: false, b: false)),
      ])
  }

  @Test(
    "MSF scanner malformed and interrupted pulse sequences remain one unknown second",
    arguments: [
      ("malformed first fall", 0), ("short B completion", 1),
      ("measured short B pulse", 2), ("wrong first polarity", 3),
      ("wrong B-start polarity", 4), ("wrong B-fall polarity", 5),
      ("missing first fall", 6), ("missing B fall", 7),
    ])
  func damagedPulseSequences(_ scenarioName: String, _ scenario: Int) {
    var scan = scanAtFirstRise()
    switch scenario {
    case 0: scan.receiveSignalChange(.falling, at: 1_138_438)
    case 1:
      scan.receiveSignalChange(.falling, at: 1_100_000)
      scan.receiveSignalChange(.rising, at: 1_200_000)
      scan.receiveSignalChange(.falling, at: 1_220_000)
    case 2:
      scan.receiveSignalChange(.falling, at: 1_100_000)
      scan.receiveSignalChange(.rising, at: 1_177_000)
      scan.receiveSignalChange(.falling, at: 1_197_000)
    case 3: scan.receiveSignalChange(.rising, at: 1_500_000)
    case 4:
      scan.receiveSignalChange(.falling, at: 1_100_000)
      scan.receiveSignalChange(.falling, at: 1_150_000)
    case 5:
      scan.receiveSignalChange(.falling, at: 1_100_000)
      scan.receiveSignalChange(.rising, at: 1_200_000)
      scan.receiveSignalChange(.rising, at: 1_250_000)
    case 6: break
    default:
      scan.receiveSignalChange(.falling, at: 1_100_000)
      scan.receiveSignalChange(.rising, at: 1_200_000)
    }
    #expect(scan.recordedCount == 0, Comment(rawValue: scenarioName))
    if scenario < 6 { #expect(MSFScannerHostOutputs.diagnostics.last?.event == 1) }
    scan.receiveSignalChange(.rising, at: 2_000_000)
    #expect(scanHistory(scan) == [nil])
    scan.receiveSignalChange(.falling, at: 2_200_000)
    #expect(scanHistory(scan) == [nil, .bits(MSFBits(a: true, b: false))])
  }

  @Test("MSF scanner noisy edges damage once and append one unknown at the boundary")
  func repeatedNoise() {
    var scan = scanAtFirstRise()
    for (edge, timestamp): (MSFScan.SignalChange, UInt64) in [
      (.falling, 1_138_000), (.rising, 1_177_000), (.falling, 1_197_000),
      (.rising, 1_884_000), (.falling, 1_889_000),
    ] { scan.receiveSignalChange(edge, at: timestamp) }
    #expect(scan.recordedCount == 0)
    #expect(MSFScannerHostOutputs.diagnostics.filter { $0.event == 1 }.count == 1)
    scan.receiveSignalChange(.rising, at: 2_000_000)
    #expect(scanHistory(scan) == [nil])
    #expect(MSFScannerHostOutputs.diagnostics.filter { $0.event == 2 }.count == 1)
  }

  @Test(
    "MSF scanner completed pairs survive late glitches and remain followed by clean pairs",
    arguments: [
      MSFBits(a: false, b: true), MSFBits(a: true, b: false), MSFBits(a: true, b: true),
    ])
  func completedPairSurvivesNoise(_ pair: MSFBits) {
    var scan = scanAtFirstRise()
    emitPulseBody(pair, into: &scan, afterRiseAt: 1_000_000)
    scan.receiveSignalChange(.rising, at: 1_884_000)
    scan.receiveSignalChange(.falling, at: 1_889_000)
    #expect(scanHistory(scan) == [.bits(pair)])
    scan.receiveSignalChange(.rising, at: 2_000_000)
    #expect(MSFScannerHostOutputs.diagnostics.last?.event == 0)
    emitPulseBody(MSFBits(a: false, b: false), into: &scan, afterRiseAt: 2_000_000)
    scan.receiveSignalChange(.rising, at: 3_000_000)
    #expect(scanHistory(scan) == [.bits(pair), .bits(MSFBits(a: false, b: false))])
  }

  @Test(
    "MSF scanner accepts every clean pair class immediately after damaged reception",
    arguments: [
      MSFBits(a: false, b: false), MSFBits(a: false, b: true),
      MSFBits(a: true, b: false), MSFBits(a: true, b: true),
    ])
  func cleanPairAfterDamage(_ pair: MSFBits) {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_138_000)
    emitSecond(pair, into: &scan, at: 2_000_000)
    scan.receiveSignalChange(.rising, at: 3_000_000)
    #expect(scanHistory(scan) == [nil, .bits(pair)])
  }

  @Test("MSF scanner does not compress adjacent damaged seconds")
  func adjacentDamage() {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_138_000)
    scan.receiveSignalChange(.rising, at: 2_000_000)
    scan.receiveSignalChange(.falling, at: 2_138_000)
    scan.receiveSignalChange(.rising, at: 3_000_000)
    scan.receiveSignalChange(.falling, at: 3_200_000)
    #expect(scanHistory(scan) == [nil, nil, .bits(MSFBits(a: true, b: false))])
  }

  @Test("MSF scanner real measured coast recovery preserves accepted data and phase diagnostics")
  func measuredCoastRecovery() throws {
    var scan = scanAtFirstRise()
    for (edge, timestamp): (MSFScan.SignalChange, UInt64) in [
      (.falling, 1_203_136), (.rising, 1_412_133), (.falling, 1_439_370),
      (.rising, 1_944_515), (.falling, 2_106_805),
    ] { scan.receiveSignalChange(edge, at: timestamp) }
    #expect(scanHistory(scan) == [.bits(MSFBits(a: true, b: false))])
    #expect(MSFScannerHostOutputs.diagnostics.last?.event == 3)
    scan.receiveSignalChange(.rising, at: 2_987_546)
    let recovery = try #require(MSFScannerHostOutputs.diagnostics.last)
    #expect(recovery.event == 4 && recovery.resetReason == 0)
    #expect(recovery.phaseStep == 2 && recovery.missingSlots == 1)
    #expect(recovery.phaseError == -12_454)
    #expect(recovery.sinceSecond == 1_987_546 && recovery.sincePrevious == 880_741)
    #expect(recovery.scanIndex == 1 && recovery.rising)
    #expect(scanHistory(scan) == [.bits(MSFBits(a: true, b: false)), nil])
    emitPulseBody(MSFBits(a: false, b: false), into: &scan, afterRiseAt: 2_987_546)
    scan.receiveSignalChange(.rising, at: 3_987_546)
    #expect(
      scanHistory(scan) == [
        .bits(MSFBits(a: true, b: false)), nil, .bits(MSFBits(a: false, b: false)),
      ])
  }

  @Test(
    "MSF scanner missed boundaries leave unconfirmed A0 B0 and damaged seconds unknown",
    arguments: [false, true])
  func missedUnconfirmedSecond(_ damaged: Bool) {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: damaged ? 1_138_000 : 1_100_000)
    #expect(scan.recordedCount == 0)
    if damaged { scan.receiveSignalChange(.falling, at: 2_106_805) }
    scan.receiveSignalChange(.rising, at: 2_987_546)
    #expect(scanHistory(scan) == [nil, nil])
    #expect(MSFScannerHostOutputs.diagnostics.last?.phaseStep == 2)
    #expect(MSFScannerHostOutputs.diagnostics.last?.missingSlots == 2)
  }

  @Test(
    "MSF scanner measured phase-aligned rises preserve completed and pending pairs outside the direct window",
    arguments: [UInt64(967_800), 1_037_462], [false, true])
  func measuredPhaseBoundaries(_ interval: UInt64, _ a: Bool) {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: a ? 1_200_000 : 1_100_000)
    scan.receiveSignalChange(.rising, at: 1_000_000 + interval)
    #expect(scanHistory(scan) == [.bits(MSFBits(a: a, b: false))])
    #expect(MSFScannerHostOutputs.diagnostics.last?.event == 4)
    #expect(MSFScannerHostOutputs.diagnostics.last?.missingSlots == 0)
    #expect(MSFScannerHostOutputs.diagnostics.last?.phaseError == Int32(interval) - 1_000_000)
  }

  @Test(
    "MSF scanner phase recovery inserts every wholly missing slot up to the five-slot limit",
    arguments: [UInt64(2), 3, 4, 5, 6])
  func missingSlotCounts(_ step: UInt64) throws {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_200_000)
    let next = 1_000_000 + step * 1_000_000
    scan.receiveSignalChange(.rising, at: next)
    #expect(scan.recordedCount == Int(step))
    #expect(scan.recordedSecond(at: 0) == .bits(MSFBits(a: true, b: false)))
    #expect(scanHistory(scan).dropFirst().allSatisfy { $0 == nil })
    let diagnostic = try #require(MSFScannerHostOutputs.diagnostics.last)
    #expect(diagnostic.event == 4 && diagnostic.phaseStep == UInt8(step))
    #expect(diagnostic.missingSlots == UInt8(step - 1) && diagnostic.resetReason == 0)
    scan.receiveSignalChange(.falling, at: next + 200_000)
    #expect(scan.recordedSecond(at: Int(step)) == .bits(MSFBits(a: true, b: false)))
  }

  @Test(
    "MSF scanner phase recovery includes exact forty-millisecond limits",
    arguments: [Int64(-40_000), -39_999, 39_999, 40_000])
  func phaseToleranceInclusive(_ error: Int64) {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_200_000)
    scan.receiveSignalChange(.rising, at: UInt64(2_000_000 + error))
    #expect(scanHistory(scan) == [.bits(MSFBits(a: true, b: false))])
    #expect(MSFScannerHostOutputs.diagnostics.last?.event == 4)
    #expect(MSFScannerHostOutputs.diagnostics.last?.phaseStep == 1)
    #expect(MSFScannerHostOutputs.diagnostics.last?.phaseError == Int32(error))
  }

  @Test(
    "MSF scanner rejects rises one microsecond beyond the phase window",
    arguments: [Int64(-40_001), 40_001])
  func phaseToleranceExclusive(_ error: Int64) {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_200_000)
    scan.receiveSignalChange(.rising, at: UInt64(2_000_000 + error))
    #expect(scanHistory(scan) == [.bits(MSFBits(a: true, b: false))])
    #expect(MSFScannerHostOutputs.diagnostics.last?.event != 4)
    if error < 0 {
      scan.receiveSignalChange(.falling, at: 1_965_000)
      scan.receiveSignalChange(.rising, at: 2_000_000)
      scan.receiveSignalChange(.falling, at: 2_200_000)
      #expect(
        scanHistory(scan) == [
          .bits(MSFBits(a: true, b: false)), .bits(MSFBits(a: true, b: false)),
        ])
    } else {
      #expect(MSFScannerHostOutputs.diagnostics.last?.event == 3)
      scan.receiveSignalChange(.rising, at: 3_000_000)
      #expect(scanHistory(scan) == [.bits(MSFBits(a: true, b: false)), nil])
      #expect(MSFScannerHostOutputs.diagnostics.last?.phaseStep == 2)
    }
  }

  @Test("MSF scanner junk cannot move the fixed phase anchor")
  func fixedPhaseThroughJunk() {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_200_000)
    for (edge, timestamp): (MSFScan.SignalChange, UInt64) in [
      (.rising, 1_412_133), (.falling, 1_439_370),
      (.rising, 1_944_515), (.falling, 2_106_805),
      (.rising, 2_300_000), (.falling, 2_350_000),
      (.rising, 3_930_000), (.falling, 3_940_000),
    ] { scan.receiveSignalChange(edge, at: timestamp) }
    #expect(scanHistory(scan) == [.bits(MSFBits(a: true, b: false))])
    scan.receiveSignalChange(.rising, at: 4_012_000)
    #expect(scanHistory(scan) == [.bits(MSFBits(a: true, b: false)), nil, nil])
    #expect(MSFScannerHostOutputs.diagnostics.last?.phaseStep == 3)
    #expect(MSFScannerHostOutputs.diagnostics.last?.phaseError == 12_000)
  }

  @Test("MSF scanner early measured junk cannot become a new phase boundary")
  func earlyMeasuredJunk() {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_200_000)
    scan.receiveSignalChange(.rising, at: 1_944_515)
    #expect(MSFScannerHostOutputs.diagnostics.last?.event != 4)
    #expect(scan.recordedCount == 1)
    scan.receiveSignalChange(.falling, at: 2_106_805)
    scan.receiveSignalChange(.rising, at: 3_000_000)
    #expect(scanHistory(scan) == [.bits(MSFBits(a: true, b: false)), nil])
    #expect(MSFScannerHostOutputs.diagnostics.last?.phaseStep == 2)
  }

  @Test("MSF scanner accepted direct jitter does not accumulate into the phase anchor")
  func fixedPhaseThroughJitter() {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_200_000)
    scan.receiveSignalChange(.rising, at: 2_025_000)
    scan.receiveSignalChange(.falling, at: 2_225_000)
    scan.receiveSignalChange(.rising, at: 3_050_000)
    scan.receiveSignalChange(.falling, at: 3_250_000)
    scan.receiveSignalChange(.rising, at: 4_000_000)
    #expect(scanHistory(scan) == Array(repeating: .bits(MSFBits(a: true, b: false)), count: 3))
    #expect(MSFScannerHostOutputs.diagnostics.last?.event == 4)
    #expect(MSFScannerHostOutputs.diagnostics.last?.phaseError == 0)
  }

  @Test(
    "MSF scanner recovers a missing pulse after 35 minutes without shifting logical slots",
    arguments: [Int64(-20), 0, 20], [30, 59, 60, 61])
  func cumulativePhaseDrift(_ drift: Int64, _ missingOffset: Int) throws {
    let missing = 35 * 60 + missingOffset
    let recovered = missing + 1
    let closing = (missing / 60 + 1) * 60
    let ordinaryPair = MSFBits(a: true, b: false)
    let recoveredPair = MSFBits(a: false, b: true)
    func start(_ slot: Int) -> UInt64 { UInt64(1_000_000 + Int64(slot) * (1_000_000 + drift)) }

    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: start(0) + 500_000)
    for slot in 1..<missing {
      if slot.isMultiple(of: 60) {
        scan.receiveSignalChange(.rising, at: start(slot))
        scan.receiveSignalChange(.falling, at: start(slot) + 500_000)
      } else {
        emitSecond(ordinaryPair, into: &scan, at: start(slot))
      }
    }
    let beforeGap = MSFScannerHostOutputs.diagnostics
    #expect(beforeGap.allSatisfy { $0.resetReason == 0 && $0.event != 4 })
    #expect(MSFScannerHostOutputs.frames.count == (missing - 1) / 60)
    #expect(MSFScannerHostOutputs.frames.allSatisfy { $0.dataCount == 59 && $0.unknownBits == 0 })

    for slot in recovered...max(closing, recovered + 2) {
      scan.receiveSignalChange(.rising, at: start(slot))
      if slot == recovered {
        let diagnostic = try #require(MSFScannerHostOutputs.diagnostics.last)
        #expect(diagnostic.event == 4)
        #expect(diagnostic.phaseStep == 2 && diagnostic.missingSlots == 1)
        let precedingMarker = (missingOffset == 61 ? 36 : 35) * 60
        #expect(diagnostic.phaseError == Int32(Int64(recovered - precedingMarker + 1) * drift))
      }
      if slot == recovered + 2 {
        let display = scan.displaySnapshot(at: start(slot) + (drift > 0 ? 170_000 : 130_000))
        #expect(display.secondPhaseBin == 1)
        #expect(display.seconds[3] == .absent)  // The start of the missing slot was never observed.
        #expect(
          display.seconds[2] == (missingOffset == 61 ? .decoded(.minuteMarker) : .decoded(.bits(ordinaryPair))))
        #expect(
          display.seconds[4] == (missingOffset == 59 ? .decoded(.minuteMarker) : .decoded(.bits(recoveredPair))))
      }
      if slot.isMultiple(of: 60) {
        scan.receiveSignalChange(.falling, at: start(slot) + 500_000)
      } else {
        emitPulseBody(slot == recovered ? recoveredPair : ordinaryPair, into: &scan, afterRiseAt: start(slot))
      }
    }

    #expect(MSFScannerHostOutputs.diagnostics.allSatisfy { $0.resetReason == 0 })
    let frame = try #require(MSFScannerHostOutputs.frames.last)
    #expect(frame.closingMarkerTime == start(closing))
    #expect(frame.hasOpeningMarker == (missingOffset == 30 || missingOffset == 61))
    #expect(frame.dataCount == (missingOffset == 60 ? 99 : 59))
    let gapMask = UInt64(1) << (closing - missing - 1)
    #expect(frame.unknownBits == gapMask)
    let bBits = recovered == closing ? UInt64(0) : (UInt64(1) << (closing - recovered - 1))
    #expect(frame.bBits == bBits)
    let dataMask = frame.dataCount < 64 ? (UInt64(1) << frame.dataCount) - 1 : .max
    #expect(frame.aBits == dataMask & ~(gapMask | bBits))
  }

  @Test(
    "MSF refreshed phase keeps the exact recovery window despite an isolated jittered start",
    arguments: [(58, Int64(-25_000)), (59, 25_000), (60, -25_000), (60, 25_000)],
    [Int64(-40_001), -40_000, 40_000, 40_001])
  func refreshedPhaseThroughJitter(_ jitter: (slot: Int, error: Int64), _ recoveryError: Int64) throws {
    let pair = MSFBits(a: true, b: false)
    // Accumulate 60 ms of drift, then settle so the last three pulses agree
    // on the new grid except for the deliberately isolated jitter.
    func nominalStart(_ slot: Int) -> Int64 { 1_000_000 + Int64(slot * 1_000_000 + min(slot, 40) * 1_500) }
    func actualStart(_ slot: Int) -> UInt64 {
      UInt64(nominalStart(slot) + (slot == jitter.slot ? jitter.error : 0))
    }

    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_500_000)
    for slot in 1..<60 {
      emitSecond(pair, into: &scan, at: actualStart(slot))
    }
    scan.receiveSignalChange(.rising, at: actualStart(60))
    scan.receiveSignalChange(.falling, at: actualStart(60) + 500_000)
    let frame = try #require(MSFScannerHostOutputs.frames.last)
    #expect(frame.closingMarkerTime == actualStart(60) && frame.hasOpeningMarker && frame.dataCount == 59)
    scan.receiveSignalChange(.rising, at: UInt64(nominalStart(60) + 650_000))
    scan.receiveSignalChange(.falling, at: UInt64(nominalStart(60) + 670_000))
    #expect(MSFScannerHostOutputs.diagnostics.last?.event == 0)

    let count = scan.recordedCount
    let next = UInt64(nominalStart(62) + recoveryError)
    scan.receiveSignalChange(.rising, at: next)
    let recovery = try #require(MSFScannerHostOutputs.diagnostics.last)
    if abs(recoveryError) == 40_000 {
      #expect(recovery.event == 4 && recovery.phaseStep == 2 && recovery.missingSlots == 1)
      #expect(recovery.phaseError == Int32(recoveryError))
      #expect(scan.recordedCount == count + 1)
    } else {
      #expect(recovery.event == 3 && scan.recordedCount == count)
      scan.receiveSignalChange(.falling, at: next + 100_000)
      scan.receiveSignalChange(.rising, at: UInt64(nominalStart(63)))
      let retried = try #require(MSFScannerHostOutputs.diagnostics.last)
      #expect(retried.event == 4 && retried.phaseStep == 3 && retried.missingSlots == 2)
      #expect(retried.phaseError == 0)
      #expect(scan.recordedCount == count + 2)
    }
    #expect(MSFScannerHostOutputs.diagnostics.allSatisfy { $0.resetReason == 0 })

    let lastAccepted = abs(recoveryError) == 40_000 ? 62 : 63
    let expired = UInt64(nominalStart(lastAccepted + 6) + 40_001)
    scan.receiveSignalChange(.falling, at: expired)
    #expect(MSFScannerHostOutputs.diagnostics.last?.resetReason == 2)
    #expect(scan.recordedCount == 0)
    #expect(scan.displaySnapshot(at: expired).secondPhaseBin == nil)
  }

  @Test(
    "MSF scanner final coasting boundary remains recoverable at both inclusive phase limits",
    arguments: [Int64(-40_000), 0, 40_000])
  func lastCoastBoundaryInclusive(_ error: Int64) {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_200_000)
    let rise = UInt64(7_000_000 + error)
    scan.receiveSignalChange(.rising, at: rise)
    #expect(scan.recordedCount == 6)
    #expect(scan.recordedSecond(at: 0) == .bits(MSFBits(a: true, b: false)))
    #expect(scanHistory(scan).dropFirst().allSatisfy { $0 == nil })
    #expect(MSFScannerHostOutputs.diagnostics.last?.resetReason == 0)
    #expect(MSFScannerHostOutputs.diagnostics.last?.phaseStep == 6)
    #expect(MSFScannerHostOutputs.diagnostics.last?.missingSlots == 5)
    #expect(MSFScannerHostOutputs.diagnostics.last?.phaseError == Int32(error))
    scan.receiveSignalChange(.falling, at: rise + 200_000)
    #expect(scan.recordedSecond(at: 6) == .bits(MSFBits(a: true, b: false)))
  }

  @Test(
    "MSF scanner coast expires immediately beyond its last recoverable boundary",
    arguments: [(UInt64(7_040_001), false), (7_050_000, false), (8_000_000, true)])
  func coastExpiration(_ timestamp: UInt64, _ rising: Bool) throws {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_200_000)
    scan.receiveSignalChange(rising ? .rising : .falling, at: timestamp)
    #expect(scan.recordedCount == 0)
    let diagnostic = try #require(MSFScannerHostOutputs.diagnostics.last)
    #expect(diagnostic.resetReason == 2)
    #expect(diagnostic.scanIndex == 1)
    #expect(diagnostic.sinceSecond == timestamp - 1_000_000)
    // A later fall-to-rise pair establishes a fresh phase, with no old entries.
    scan.receiveSignalChange(.falling, at: timestamp + 100_000)
    scan.receiveSignalChange(.rising, at: timestamp + 1_000_000)
    scan.receiveSignalChange(.falling, at: timestamp + 1_100_000)
    scan.receiveSignalChange(.rising, at: timestamp + 2_000_000)
    #expect(scanHistory(scan) == [.bits(MSFBits(a: false, b: false))])
  }

  @Test("MSF scanner allows the reset-causing rise itself to establish fresh phase")
  func resettingRiseReacquires() {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_200_000)
    scan.receiveSignalChange(.falling, at: 7_030_000)
    scan.receiveSignalChange(.rising, at: 7_950_000)
    #expect(MSFScannerHostOutputs.diagnostics.last?.resetReason == 2)
    #expect(scan.recordedCount == 0)
    scan.receiveSignalChange(.falling, at: 8_050_000)
    scan.receiveSignalChange(.rising, at: 8_950_000)
    #expect(scanHistory(scan) == [.bits(MSFBits(a: false, b: false))])
  }

  @Test(
    "MSF scanner backwards timestamps reset both ordinary and coasting histories",
    arguments: [false, true])
  func nonMonotonicReset(_ coasting: Bool) throws {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_200_000)
    if coasting { scan.receiveSignalChange(.falling, at: 2_106_805) }
    scan.receiveSignalChange(.rising, at: coasting ? 2_000_000 : 999_999)
    #expect(scan.recordedCount == 0)
    let diagnostic = try #require(MSFScannerHostOutputs.diagnostics.last)
    #expect(diagnostic.resetReason == 1 && diagnostic.scanIndex == 1)
    #expect(diagnostic.sincePrevious == nil)
    #expect(diagnostic.sinceSecond == (coasting ? 1_000_000 : nil))
    #expect(MSFScannerHostOutputs.frames.isEmpty)
  }

  @Test(
    "MSF scanner history rollover preserves ordering, known pairs and unknown slots",
    arguments: [0, 1, 2])
  func historyRollover(_ ending: Int) {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_500_000)
    for index in 1...98 {
      let pair = MSFBits(a: index % 2 == 0, b: index % 3 == 0)
      emitSecond(pair, into: &scan, at: 1_000_000 + UInt64(index) * 1_000_000)
    }
    if ending == 0 {
      emitSecond(MSFBits(a: false, b: true), into: &scan, at: 100_000_000)
      scan.receiveSignalChange(.rising, at: 101_000_000)
      scan.receiveSignalChange(.falling, at: 101_500_000)
    } else if ending == 1 {
      scan.receiveSignalChange(.rising, at: 100_000_000)
      scan.receiveSignalChange(.falling, at: 100_138_000)
      scan.receiveSignalChange(.rising, at: 101_000_000)
      scan.receiveSignalChange(.falling, at: 101_500_000)
    } else {
      scan.receiveSignalChange(.rising, at: 102_000_000)
      #expect(MSFScannerHostOutputs.diagnostics.last?.phaseStep == 3)
      #expect(MSFScannerHostOutputs.diagnostics.last?.missingSlots == 2)
    }
    #expect(scan.recordedCount == 100)
    // Opening marker has been evicted. All 98 accepted pairs retain order.
    for index in 1...98 {
      #expect(
        scan.recordedSecond(at: index - 1)
          == .bits(MSFBits(a: index % 2 == 0, b: index % 3 == 0)))
    }
    if ending == 0 {
      #expect(scan.recordedSecond(at: 98) == .bits(MSFBits(a: false, b: true)))
      #expect(scan.recordedSecond(at: 99) == .minuteMarker)
    } else if ending == 1 {
      #expect(
        scan.recordedSecond(at: 98) == nil && scan.recordedSecond(at: 99) == .minuteMarker)
    } else {
      #expect(scan.recordedSecond(at: 98) == nil && scan.recordedSecond(at: 99) == nil)
    }
    if ending != 2 {
      #expect(MSFScannerHostOutputs.frames.count == 1)
      #expect(MSFScannerHostOutputs.frames.first?.dataCount == 99)
      #expect(MSFScannerHostOutputs.frames.first?.hasOpeningMarker == false)
      #expect(MSFScannerHostOutputs.frames.first?.unknownBits == (ending == 1 ? 1 : 0))
    }
    #expect(scan.recordedSecond(at: 100) == nil)
    #expect(MSFScannerHostOutputs.diagnostics.allSatisfy { $0.resetReason == 0 })
  }

  @Test(
    "MSF scanner publishes exact packed physical frames with the invariant final forty-three positions",
    arguments: [
      (58, UInt64(0x155_5132_694b_c27e), UInt64(0xcc_c800_0000_0006)),
      (59, 0x2aa_a932_694b_c27e, 0x199_9800_0000_0006),
      (60, 0x555_5132_694b_c27e, 0x333_3000_0000_0006),
    ])
  func packedPhysicalFrames(_ count: Int, _ expectedA: UInt64, _ expectedB: UInt64) throws {
    let (scan, frame) = try publishedFixtureFrame(dataCount: count)
    #expect(frame.dataCount == count && frame.hasOpeningMarker)
    #expect(frame.aBits == expectedA && frame.bBits == expectedB)
    #expect(frame.unknownBits == 0)
    #expect(frame.closingMarkerTime == 2_000_000 + UInt64(count) * 1_000_000)
    #expect(scan.recordedSecond(at: 0) == .minuteMarker)
    #expect(scan.recordedSecond(at: count + 1) == .minuteMarker)
    let logical = try #require(frame.logicalFrame())
    for index in 0..<43 {
      let pair = scannerFixturePair(at: index)
      #expect(scan.recordedSecond(at: count - 42 + index) == .bits(pair))
      #expect(logical.bits(atLogicalPosition: 17 + index) == pair)
    }
    #expect(logical.analyze().fixedIdentifier == .valid)
    expectScannerFixtureDecoded(frame)
  }

  @Test("MSF scanner markerless suffixes decode without inventing an opening marker")
  func markerlessFixture() throws {
    var scan = scanAtFirstRise()
    emitPulseBody(scannerFixturePair(at: 0), into: &scan, afterRiseAt: 1_000_000)
    for index in 1..<43 {
      emitSecond(
        scannerFixturePair(at: index), into: &scan,
        at: 1_000_000 + UInt64(index) * 1_000_000)
    }
    scan.receiveSignalChange(.rising, at: 44_000_000)
    #expect(MSFScannerHostOutputs.frames.isEmpty)
    scan.receiveSignalChange(.falling, at: 44_500_000)
    #expect(MSFScannerHostOutputs.frames.count == 1)
    let frame = try #require(MSFScannerHostOutputs.frames.first)
    #expect(frame.dataCount == 43 && !frame.hasOpeningMarker)
    #expect(frame.aBits == scannerFixtureA && frame.bBits == scannerFixtureB)
    #expect(frame.closingMarkerTime == 44_000_000)
    expectScannerFixtureDecoded(frame)
  }

  @Test(
    "MSF scanner closing publication waits for marker validation and records its rising timestamp",
    arguments: [UInt64(470_000), 500_000, 530_000])
  func publicationTime(_ markerWidth: UInt64) throws {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_500_000)
    emitSecond(MSFBits(a: true, b: false), into: &scan, at: 2_000_000)
    scan.receiveSignalChange(.rising, at: 3_000_000)
    #expect(MSFScannerHostOutputs.frames.isEmpty)
    scan.receiveSignalChange(.falling, at: 3_000_000 + markerWidth)
    #expect(MSFScannerHostOutputs.frames.count == 1)
    let frame = try #require(MSFScannerHostOutputs.frames.first)
    #expect(frame.closingMarkerTime == 3_000_000)
    #expect(frame.closingMarkerTime != 3_000_000 + markerWidth)
    #expect(frame.dataCount == 1 && frame.hasOpeningMarker)
    #expect(frame.aBits == 1 && frame.bBits == 0 && frame.unknownBits == 0)
    // Later processing or snapshot reads must not rewrite the published timestamp.
    _ = scan.displaySnapshot(at: 4_500_000)
    #expect(MSFScannerHostOutputs.frames.count == 1)
    #expect(MSFScannerHostOutputs.frames.first?.closingMarkerTime == 3_000_000)
  }

  @Test(
    "MSF scanner malformed closing marker cannot fabricate a frame or lose its unknown position"
  )
  func malformedClosingMarker() throws {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_500_000)
    for index in 0..<58 {
      emitSecond(
        MSFBits(a: false, b: false), into: &scan, at: 2_000_000 + UInt64(index) * 1_000_000)
    }
    scan.receiveSignalChange(.rising, at: 60_000_000)
    scan.receiveSignalChange(.falling, at: 60_138_000)
    #expect(MSFScannerHostOutputs.frames.isEmpty && scan.recordedCount == 59)
    scan.receiveSignalChange(.rising, at: 61_000_000)
    #expect(scan.recordedCount == 60 && scan.recordedSecond(at: 59) == nil)
    #expect(MSFScannerHostOutputs.frames.isEmpty)
    scan.receiveSignalChange(.falling, at: 61_500_000)
    let frame = try #require(MSFScannerHostOutputs.frames.first)
    #expect(MSFScannerHostOutputs.frames.count == 1)
    #expect(frame.unknownBits == 1 && !frame.hasOpeningMarker)
    #expect(frame.decode().decodeStatus == .missingData)
  }

  @Test(
    "MSF scanner damaged seconds preserve bit positions before, inside and after the required suffix",
    arguments: [0, 5, 16, 30, 58])
  func damagedFramePositions(_ position: Int) throws {
    let (scan, frame) = try publishedFixtureFrame(damaged: [position])
    let mask = UInt64(1) << (58 - position)
    #expect(frame.dataCount == 59 && frame.unknownBits == mask)
    #expect(frame.aBits & mask == 0 && frame.bBits & mask == 0)
    #expect(scan.recordedSecond(at: position + 1) == nil)
    #expect(scan.recordedSecond(at: 0) == .minuteMarker)
    #expect(scan.recordedSecond(at: 60) == .minuteMarker)
    if position < 16 {
      #expect(frame.hasOpeningMarker)
      expectScannerFixtureDecoded(frame)
    } else {
      #expect(frame.decode().decodeStatus == .missingData)
      #expect(frame.decode().calendarDateTime == nil)
    }
  }

  @Test(
    "MSF scanner wholly missed slots preserve opening trust until a closing marker becomes ambiguous",
    arguments: [([5], true), ([5, 6], true), ([30], true), ([58], false)])
  func missingFramePositions(_ positions: [Int], _ trustedOpening: Bool) throws {
    let (scan, frame) = try publishedFixtureFrame(
      missing: Set(positions), completedPrefix: true)
    let expectedUnknown = positions.reduce(UInt64(0)) { $0 | (UInt64(1) << (58 - $1)) }
    #expect(frame.dataCount == 59 && frame.hasOpeningMarker == trustedOpening)
    #expect(frame.unknownBits == expectedUnknown)
    #expect(scan.recordedSecond(at: 0) == .minuteMarker)
    #expect(scan.recordedSecond(at: 60) == .minuteMarker)
    for position in positions { #expect(scan.recordedSecond(at: position + 1) == nil) }
    if positions.allSatisfy({ $0 < 16 }) {
      expectScannerFixtureDecoded(frame)
    } else {
      #expect(frame.decode().decodeStatus == .missingData)
    }
  }

  @Test(
    "MSF scanner a lost boundary also marks its preceding unconfirmed A0 B0 as unknown",
    arguments: [[5], [5, 6]])
  func unconfirmedPrefixBeforeGap(_ missing: [Int]) throws {
    let (scan, frame) = try publishedFixtureFrame(missing: Set(missing))
    // The cyclic prefix's position 4 is A0/B0. Its confirmation boundary
    // at position 5 was never received, unlike the completed-prefix fixture.
    let unknownPositions = [4] + missing
    let mask = unknownPositions.reduce(UInt64(0)) { $0 | (UInt64(1) << (58 - $1)) }
    #expect(frame.unknownBits == mask && frame.hasOpeningMarker)
    for position in unknownPositions {
      #expect(scan.recordedSecond(at: position + 1) == nil)
    }
    expectScannerFixtureDecoded(frame)
  }

  @Test("MSF scanner a genuine marker after an ambiguous gap restores trust for the next frame")
  func markerTrustRestored() throws {
    var (scan, first) = try publishedFixtureFrame(missing: [58])
    #expect(!first.hasOpeningMarker)
    for index in 0..<59 {
      emitSecond(
        physicalFixturePair(at: index, dataCount: 59), into: &scan,
        at: 62_000_000 + UInt64(index) * 1_000_000)
    }
    scan.receiveSignalChange(.rising, at: 121_000_000)
    #expect(MSFScannerHostOutputs.frames.count == 1)
    scan.receiveSignalChange(.falling, at: 121_500_000)
    #expect(MSFScannerHostOutputs.frames.count == 2)
    let second = try #require(MSFScannerHostOutputs.frames.last)
    #expect(second.hasOpeningMarker && second.dataCount == 59)
    #expect(second.closingMarkerTime == 121_000_000)
    expectScannerFixtureDecoded(second)
  }

  @Test("MSF scanner phase recovery invents neither an opening marker nor known missing bits")
  func missingWithoutOpening() throws {
    var scan = scanAtFirstRise()
    scan.receiveSignalChange(.falling, at: 1_200_000)
    scan.receiveSignalChange(.rising, at: 4_000_000)
    scan.receiveSignalChange(.falling, at: 4_500_000)
    #expect(scanHistory(scan) == [.bits(MSFBits(a: true, b: false)), nil, nil, .minuteMarker])
    let frame = try #require(MSFScannerHostOutputs.frames.first)
    #expect(MSFScannerHostOutputs.frames.count == 1)
    #expect(!frame.hasOpeningMarker && frame.dataCount == 3)
    #expect(frame.aBits == 4 && frame.bBits == 0 && frame.unknownBits == 3)
  }
}

private func scanAtFirstRise(polarity: MSFScan.Polarity = .carrierPresentLow) -> MSFScan {
  var scan = MSFScan(polarity: polarity)
  receiveFixtureEdge(.falling, into: &scan, at: 100_000, polarity: polarity)
  receiveFixtureEdge(.rising, into: &scan, at: 1_000_000, polarity: polarity)
  #expect(scan.recordedCount == 0)
  return scan
}

private func scanHistory(_ scan: MSFScan) -> [MSFSecond?] {
  (0..<scan.recordedCount).map { scan.recordedSecond(at: $0) }
}

// Fixtures describe carrier interruptions in the original active-low convention.
private func receiveFixtureEdge(
  _ change: MSFScan.SignalChange, into scan: inout MSFScan, at time: UInt64,
  polarity: MSFScan.Polarity
) {
  let physical: MSFScan.SignalChange =
    polarity == .carrierPresentLow
    ? change : (change == .rising ? .falling : .rising)
  scan.receiveSignalChange(physical, at: time)
}

private func emitPulseBody(
  _ pair: MSFBits, into scan: inout MSFScan, afterRiseAt start: UInt64,
  polarity: MSFScan.Polarity = .carrierPresentLow
) {
  if pair.a {
    receiveFixtureEdge(
      .falling, into: &scan,
      at: start + (pair.b ? 300_000 : 200_000), polarity: polarity)
  } else {
    receiveFixtureEdge(.falling, into: &scan, at: start + 100_000, polarity: polarity)
    if pair.b {
      receiveFixtureEdge(.rising, into: &scan, at: start + 200_000, polarity: polarity)
      receiveFixtureEdge(.falling, into: &scan, at: start + 300_000, polarity: polarity)
    }
  }
}

private func emitSecond(
  _ pair: MSFBits, into scan: inout MSFScan, at start: UInt64,
  polarity: MSFScan.Polarity = .carrierPresentLow
) {
  receiveFixtureEdge(.rising, into: &scan, at: start, polarity: polarity)
  emitPulseBody(pair, into: &scan, afterRiseAt: start, polarity: polarity)
}

// Fixed independent archived transmission: 2026-09-29 Tuesday 17:42, BST.
private let scannerFixtureA: UInt64 = 0x132_694b_c27e
private let scannerFixtureB: UInt64 = 0x6

private func scannerFixturePair(at index: Int) -> MSFBits {
  let mask = UInt64(1) << (42 - index)
  return MSFBits(a: scannerFixtureA & mask != 0, b: scannerFixtureB & mask != 0)
}

private func physicalFixturePair(at index: Int, dataCount: Int) -> MSFBits {
  let prefix = dataCount - 43
  if index < prefix {
    // Independently recognizable repeating prefix: 00, 10, 01, 11.
    return MSFBits(a: index % 2 == 1, b: index % 4 >= 2)
  }
  return scannerFixturePair(at: index - prefix)
}

private func publishedFixtureFrame(
  dataCount: Int = 59, damaged: Set<Int> = [], missing: Set<Int> = [],
  completedPrefix: Bool = false, polarity: MSFScan.Polarity = .carrierPresentLow
)
  throws -> (MSFScan, MSFCompletedFrame)
{
  var scan = scanAtFirstRise(polarity: polarity)
  receiveFixtureEdge(.falling, into: &scan, at: 1_500_000, polarity: polarity)
  for index in 0..<dataCount where !missing.contains(index) {
    let start = 2_000_000 + UInt64(index) * 1_000_000
    if damaged.contains(index) {
      receiveFixtureEdge(.rising, into: &scan, at: start, polarity: polarity)
      receiveFixtureEdge(.falling, into: &scan, at: start + 138_438, polarity: polarity)
    } else {
      // Gap fixtures use already-completed prefix pairs to isolate the
      // deliberately omitted slots from unconfirmed A0/B0 observations.
      let pair =
        completedPrefix && index < dataCount - 43
        ? MSFBits(a: true, b: false)
        : physicalFixturePair(at: index, dataCount: dataCount)
      emitSecond(pair, into: &scan, at: start, polarity: polarity)
    }
  }
  let closingRise = 2_000_000 + UInt64(dataCount) * 1_000_000
  receiveFixtureEdge(.rising, into: &scan, at: closingRise, polarity: polarity)
  #expect(MSFScannerHostOutputs.frames.isEmpty)
  receiveFixtureEdge(.falling, into: &scan, at: closingRise + 500_000, polarity: polarity)
  #expect(MSFScannerHostOutputs.frames.count == 1)
  return (scan, try #require(MSFScannerHostOutputs.frames.first))
}

private func expectScannerFixtureDecoded(_ frame: MSFCompletedFrame) {
  let decoded = frame.decode()
  #expect(decoded.decodeStatus == .valid)
  #expect(
    decoded.calendarDateTime
      == CalendarDateTimeComponents(
        year: 2026, month: 9,
        dayOfMonth: 29, dayOfWeek: 2, hour: 17, minute: 42, second: 0, timeZone: nil))
  #expect(frame.summerTime == true)
}
