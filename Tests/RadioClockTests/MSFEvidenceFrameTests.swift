//
//  MSFEvidenceFrameTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-13.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

@Test(
  "MSF epistemic operations reach the requested confidence band",
  arguments: [
    (EpistemicState.unknown, UInt8(0)), (.candidate, 10),
    (.supported, 20), (.confirmed, 30),
  ], [false, true])
func evidenceValueInitialization(_ sample: (EpistemicState, UInt8), _ value: Bool) {
  let (state, confidence) = sample
  var evidence = MSFEpistemicValue<Bool>()
  #expect((evidence.value == nil) == (evidence.confidence == 0))
  for _ in 0..<Int(confidence) {
    evidence.observeSameLogicalValue(value)
    #expect((evidence.value == nil) == (evidence.confidence == 0))
  }
  #expect(evidence.confidence == confidence)
  #expect(evidence.state == state)
  #expect(evidence.value == (state == .unknown ? nil : value))
}

@Test(
  "MSF matching observations accumulate confidence through all bands and saturate at thirty",
  arguments: [
    (0, UInt8(0), EpistemicState.unknown), (1, 1, .candidate),
    (10, 10, .candidate), (11, 11, .supported), (20, 20, .supported),
    (21, 21, .confirmed), (29, 29, .confirmed), (30, 30, .confirmed),
    (31, 30, .confirmed), (255, 30, .confirmed),
  ], [false, true])
func evidenceValueAccumulation(_ sample: (Int, UInt8, EpistemicState), _ observed: Bool) {
  let (count, confidence, state) = sample
  var evidence = MSFEpistemicValue<Bool>()
  #expect((evidence.value == nil) == (evidence.confidence == 0))
  for index in 0..<count {
    let result = evidence.observeSameLogicalValue(observed)
    #expect(result == (index == 0 ? .seeded : .reinforced))
    #expect((evidence.value == nil) == (evidence.confidence == 0))
  }
  #expect(evidence.value == (count == 0 ? nil : observed))
  #expect(evidence.confidence == confidence)
  #expect(evidence.state == state)
}

@Test(
  "MSF missing observations degrade confidence and clear the value exactly at zero",
  arguments: [
    (0, UInt8(30), EpistemicState.confirmed), (1, 29, .confirmed),
    (9, 21, .confirmed), (10, 20, .supported), (19, 11, .supported),
    (20, 10, .candidate), (29, 1, .candidate), (30, 0, .unknown),
    (31, 0, .unknown), (255, 0, .unknown),
  ], [false, true])
func evidenceValueAging(_ sample: (Int, UInt8, EpistemicState), _ original: Bool) {
  let (count, confidence, state) = sample
  var missing = MSFEpistemicValue<Bool>()
  #expect((missing.value == nil) == (missing.confidence == 0))
  missing.confirmValidatedValue(original)
  #expect((missing.value == nil) == (missing.confidence == 0))
  var explicitlyAged = missing
  for _ in 0..<count {
    #expect(missing.observeSameLogicalValue(nil) == .aged)
    explicitlyAged.age()
    #expect((missing.value == nil) == (missing.confidence == 0))
    #expect((explicitlyAged.value == nil) == (explicitlyAged.confidence == 0))
  }
  #expect(missing == explicitlyAged)
  #expect(missing.value == (confidence == 0 ? nil : original))
  #expect(missing.confidence == confidence)
  #expect(missing.state == state)
}

@Test(
  "MSF differing same-value observations report contradictions without weakening belief",
  arguments: [1, 10, 20, 30], [false, true])
func evidenceValueContradiction(_ confidence: Int, _ original: Bool) {
  var evidence = MSFEpistemicValue<Bool>()
  #expect((evidence.value == nil) == (evidence.confidence == 0))
  for _ in 0..<confidence {
    evidence.observeSameLogicalValue(original)
    #expect((evidence.value == nil) == (evidence.confidence == 0))
  }
  let before = evidence
  for _ in 0..<255 {
    #expect(
      evidence.observeSameLogicalValue(!original)
        == .contradiction(existing: original, observed: !original))
    #expect(evidence == before)
    #expect((evidence.value == nil) == (evidence.confidence == 0))
  }
}

@Test(
  "MSF evidence frame forwards contradictions without changing either channel",
  arguments: [MSFChannel.a, .b], [false, true])
func evidenceFrameContradictionResult(_ channel: MSFChannel, _ value: Bool) throws {
  var evidence = seededEvidence(value, count: 30, position: 45, channel: channel)
  let before = try #require(evidence.second(atLogicalPosition: 45))
  let result = evidence.observeSameLogicalValue(!value, atLogicalPosition: 45, channel: channel)
  #expect(result == .contradiction(existing: value, observed: !value))
  #expect(evidence.second(atLogicalPosition: 45) == before)
}

@Test(
  "MSF expected-value transitions preserve confidence and cannot create evidence",
  arguments: [0, 1, 10, 20, 30], [false, true])
func evidenceValueTransition(_ confidence: Int, _ original: Bool) {
  var evidence = MSFEpistemicValue<Bool>()
  #expect((evidence.value == nil) == (evidence.confidence == 0))
  for _ in 0..<confidence {
    evidence.observeSameLogicalValue(original)
    #expect((evidence.value == nil) == (evidence.confidence == 0))
  }
  let state = evidence.state
  evidence.transitionExpectedValue(to: !original)
  #expect((evidence.value == nil) == (evidence.confidence == 0))
  #expect(evidence.value == (confidence == 0 ? nil : !original))
  #expect(evidence.confidence == UInt8(confidence))
  #expect(evidence.state == state)
}

@Test(
  "MSF structural confirmation replaces prior belief with maximum confidence",
  arguments: [Optional<Bool>.none, false, true], [false, true])
func evidenceValueConfirmation(_ previous: Bool?, _ confirmed: Bool) {
  var evidence = MSFEpistemicValue<Bool>()
  #expect((evidence.value == nil) == (evidence.confidence == 0))
  if let previous {
    evidence.observeSameLogicalValue(previous)
    #expect((evidence.value == nil) == (evidence.confidence == 0))
  }
  evidence.confirmValidatedValue(confirmed)
  #expect((evidence.value == nil) == (evidence.confidence == 0))
  #expect(evidence.value == confirmed)
  #expect(evidence.confidence == 30)
  #expect(evidence.state == .confirmed)
}

@Test("MSF epistemic equality compares both the value and its confidence")
func evidenceValueEquality() {
  var candidate = MSFEpistemicValue<Bool>()
  for _ in 0..<10 { candidate.observeSameLogicalValue(true) }
  var equal = MSFEpistemicValue<Bool>()
  for _ in 0..<10 { equal.observeSameLogicalValue(true) }
  var different = MSFEpistemicValue<Bool>()
  for _ in 0..<10 { different.observeSameLogicalValue(false) }
  var supported = candidate
  for _ in 0..<10 { supported.observeSameLogicalValue(true) }
  #expect(candidate == equal)
  #expect(candidate != different)
  #expect(candidate != supported)
  var aged = candidate
  for _ in 0..<10 { aged.age() }
  #expect(MSFEpistemicValue<Bool>() == aged)
}

@Test(
  "MSF epistemic confirmation flag selects only the confirmed state",
  arguments: [
    (EpistemicState.unknown, false), (.candidate, false),
    (.supported, false), (.confirmed, true),
  ])
func evidenceStateConfirmation(_ state: EpistemicState, _ confirmed: Bool) {
  #expect(state.isConfirmed == confirmed)
}

@Test("MSF evidence starts with independent unknown values at all forty-three positions")
func evidenceFrameInitialState() throws {
  let evidence = MSFEvidenceFrame()
  for position in 17...59 {
    let second = try #require(evidence.second(atLogicalPosition: position))
    #expect(second == MSFEpistemicSecond())
    #expect(second.a.value == nil && second.a.confidence == 0 && second.a.state == .unknown)
    #expect(second.b.value == nil && second.b.confidence == 0 && second.b.state == .unknown)
  }
  #expect(evidence.epistemicState(in: 17...59) == .unknown)
}

@Test(
  "MSF confirmed predictions establish only modelled bits including optional B58",
  arguments: [false, true])
func evidenceConfirmedPrediction(_ predictSummerTime: Bool) throws {
  let evidence = MSFEvidenceFrame(
    confirmed: evidencePrediction(predictSummerTime: predictSummerTime))
  // Independent archived fixture: 2026-09-29 Tuesday 17:42, BST.
  for position in 17...59 {
    let mask = UInt64(1) << (59 - position)
    let second = try #require(evidence.second(atLogicalPosition: position))
    #expect(second.a.value == (UInt64(0x132_694b_c27e) & mask != 0))
    #expect(second.a.confidence == 30)
    if (54...57).contains(position) || (position == 58 && predictSummerTime) {
      #expect(second.b.value == (UInt64(0x6) & mask != 0))
      #expect(second.b.confidence == 30)
    } else {
      #expect(second.b == MSFEpistemicValue<Bool>())
    }
  }
}

@Test(
  "MSF confirmed logical frames retain received unmodelled bits and leave unknown pairs empty",
  arguments: [UInt64(0), 1 << 42, 1 << 1, 0x7ff_ffff_ffff])
func evidenceConfirmedLogicalFrame(_ unknown: UInt64) throws {
  let evidence = MSFEvidenceFrame(confirmed: try evidenceLogicalFrame(unknown: unknown))
  for position in 17...59 {
    let mask = UInt64(1) << (59 - position)
    let second = try #require(evidence.second(atLogicalPosition: position))
    if unknown & mask != 0 {
      #expect(second == MSFEpistemicSecond())
    } else {
      #expect(second.a.value == (UInt64(0x132_694b_c27e) & mask != 0))
      #expect(second.b.value == (UInt64(0x6) & mask != 0))
      #expect(second.a.confidence == 30)
      #expect(second.b.confidence == 30)
    }
  }
}

@Test(
  "MSF evidence position updates include both endpoints and ignore out-of-range positions",
  arguments: [Int.min, -1, 16, 17, 59, 60, Int.max])
func evidencePositionBounds(_ position: Int) {
  var evidence = MSFEvidenceFrame()
  let result = evidence.observeSameLogicalValue(true, atLogicalPosition: position, channel: .a)
  if position == 17 || position == 59 {
    #expect(result == .seeded)
    #expect(evidence.second(atLogicalPosition: position)?.a.value == true)
    #expect(evidence.second(atLogicalPosition: position)?.a.confidence == 1)
  } else {
    #expect(result == nil)
    #expect(evidence.second(atLogicalPosition: position) == nil)
  }
  for other in 17...59 where other != position {
    #expect(evidence.second(atLogicalPosition: other) == MSFEpistemicSecond())
  }
}

@Test(
  "MSF frame reinforcement accumulates on the selected channel without changing its neighbour",
  arguments: [1, 10, 11, 20, 21, 30, 31], [MSFChannel.a, .b])
func evidenceFrameReinforcement(_ count: Int, _ channel: MSFChannel) throws {
  var evidence = MSFEvidenceFrame()
  for index in 0..<count {
    #expect(
      evidence.observeSameLogicalValue(false, atLogicalPosition: 17, channel: channel)
        == (index == 0 ? .seeded : .reinforced))
  }
  let second = try #require(evidence.second(atLogicalPosition: 17))
  let selected = channel == .a ? second.a : second.b
  let other = channel == .a ? second.b : second.a
  #expect(selected.value == false)
  #expect(selected.confidence == UInt8(min(count, 30)))
  #expect(other == MSFEpistemicValue<Bool>())
  #expect(evidence.second(atLogicalPosition: 18) == MSFEpistemicSecond())
}

@Test("MSF A and B evidence age independently", arguments: [MSFChannel.a, .b])
func evidenceChannelsIndependent(_ channel: MSFChannel) throws {
  var evidence = MSFEvidenceFrame(confirmed: evidencePrediction())
  #expect(
    evidence.observeSameLogicalValue(nil, atLogicalPosition: 58, channel: channel) == .aged)
  let second = try #require(evidence.second(atLogicalPosition: 58))
  #expect(second.a.value == true && second.b.value == true)
  #expect(second.a.confidence == (channel == .a ? 29 : 30))
  #expect(second.b.confidence == (channel == .b ? 29 : 30))
}

@Test(
  "MSF range confidence uses the weakest A bit and ignores stronger B evidence",
  arguments: [
    (0, EpistemicState.unknown), (1, .candidate), (10, .candidate),
    (11, .supported), (20, .supported), (21, .confirmed), (30, .confirmed),
  ])
func evidenceRangeConfidence(_ confidence: Int, _ state: EpistemicState) {
  var evidence = MSFEvidenceFrame(confirmed: evidencePrediction())
  for _ in 0..<(30 - confidence) {
    evidence.observeSameLogicalValue(nil, atLogicalPosition: 20, channel: .a)
  }
  for _ in 0..<30 {
    evidence.observeSameLogicalValue(true, atLogicalPosition: 20, channel: .b)
  }
  #expect(evidence.epistemicState(in: 17...24) == state)
  #expect(evidence.epistemicState(in: 20...20) == state)
  #expect(evidence.epistemicState(in: 21...24) == .confirmed)
  #expect(evidence.second(atLogicalPosition: 20)?.b.confidence == 30)
}

@Test(
  "MSF confidence ranges containing an out-of-range position are unknown",
  arguments: [16...17, 59...60, 16...60])
func evidenceRangeBounds(_ positions: ClosedRange<Int>) {
  let evidence = MSFEvidenceFrame(confirmed: evidencePrediction())
  #expect(evidence.epistemicState(in: positions) == .unknown)
}

@Test(
  "MSF expected A, parity B and Summer Time transitions retain their evidence strength",
  arguments: [
    (51, MSFChannel.a, false, true), (57, .b, true, false), (58, .b, false, true),
  ], [0, 1, 10, 20, 30])
func evidenceExpectedBitTransition(_ sample: (Int, MSFChannel, Bool, Bool), _ confidence: Int) {
  let (position, channel, previous, next) = sample
  // Fixed calendar inputs independently establish A51's 26 -> 27 units-bit
  // change, its odd parity B57 change, and the explicit GMT -> BST B58 change.
  let old = evidencePrediction(day: 30, weekday: 3, hour: 13, minute: 26, summerTime: false)
  let new = evidencePrediction(day: 30, weekday: 3, hour: 13, minute: 27, summerTime: true)
  #expect(old.bit(at: position, channel: channel) == previous)
  #expect(new.bit(at: position, channel: channel) == next)
  var evidence = seededEvidence(previous, count: confidence, position: position, channel: channel)
  evidence.projectExpectedTransition(fromExpectedFrame: old, toExpectedFrame: new)
  let second = evidence.second(atLogicalPosition: position)
  let selected = channel == .a ? second?.a : second?.b
  #expect(selected?.value == (confidence == 0 ? nil : next))
  #expect(selected?.confidence == UInt8(confidence))
}

@Test("MSF unchanged predictions and unmodelled positions preserve evidence during projection")
func evidenceUnchangedBitTransition() {
  let old = evidencePrediction(day: 30, weekday: 3, hour: 13, minute: 26)
  let new = evidencePrediction(day: 30, weekday: 3, hour: 13, minute: 27)
  var evidence = MSFEvidenceFrame(confirmed: old)
  evidence.observeSameLogicalValue(true, atLogicalPosition: 17, channel: .b)
  let before17 = evidence.second(atLogicalPosition: 17)
  let before58 = evidence.second(atLogicalPosition: 58)
  #expect(old.bit(at: 17, channel: .a) == false)
  #expect(new.bit(at: 17, channel: .a) == false)
  evidence.projectExpectedTransition(fromExpectedFrame: old, toExpectedFrame: new)
  #expect(evidence.second(atLogicalPosition: 17) == before17)
  #expect(evidence.second(atLogicalPosition: 58) == before58)
}

@Test(
  "MSF projection leaves B58 evidence unchanged when either prediction is unknown",
  arguments: [false, true])
func evidenceUnknownExpectedTransition(_ oldPredicts: Bool) {
  let old = evidencePrediction(summerTime: false, predictSummerTime: oldPredicts)
  let new = evidencePrediction(summerTime: true, predictSummerTime: !oldPredicts)
  var evidence = seededEvidence(false, count: 10, position: 58, channel: .b)
  let before = evidence.second(atLogicalPosition: 58)
  evidence.projectExpectedTransition(fromExpectedFrame: old, toExpectedFrame: new)
  #expect(evidence.second(atLogicalPosition: 58) == before)
}

@Test(
  "MSF predictable-bit aging preserves unmodelled evidence and never underflows",
  arguments: [1, 30, 31], [false, true])
func evidencePredictableAging(_ count: Int, _ predictSummerTime: Bool) throws {
  var evidence = MSFEvidenceFrame(confirmed: try evidenceLogicalFrame())
  let prediction = evidencePrediction(predictSummerTime: predictSummerTime)
  for _ in 0..<count { evidence.agePredictableBits(in: prediction) }
  let confidence = UInt8(max(0, 30 - count))
  for position in 17...59 {
    let second = try #require(evidence.second(atLogicalPosition: position))
    #expect(second.a.confidence == confidence)
    #expect(
      second.a.value == (confidence == 0 ? nil : prediction.bit(at: position, channel: .a)))
    let modelledB = (54...57).contains(position) || (position == 58 && predictSummerTime)
    #expect(second.b.confidence == (modelledB ? confidence : 30))
    let receivedB = UInt64(0x6) & (UInt64(1) << (59 - position)) != 0
    #expect(second.b.value == (modelledB && confidence == 0 ? nil : receivedB))
  }
}

@Test(
  "MSF single-channel observe compares predictions and updates only justified evidence",
  arguments: [
    (Optional<Bool>.none, Bool?(false), Bool?(false), false, 9),
    (false, false, false, false, 11), (true, false, false, true, 10),
    (nil, nil, false, false, 10), (false, nil, false, false, 10),
    (true, nil, false, false, 10), (true, true, false, false, 10),
    (false, true, false, true, 10), (false, false, nil, false, 1),
    (nil, false, nil, false, 0), (true, false, nil, true, 0),
  ], [MSFChannel.a, .b])
func evidenceObserveSingleChannel(
  _ sample: (Bool?, Bool?, Bool?, Bool, Int),
  _ channel: MSFChannel
) throws {
  let (received, expected, belief, contradiction, confidence) = sample
  var evidence = seededEvidence(belief, count: 10, position: 58, channel: channel)
  #expect(
    evidence.observe(
      receivedBool: received, expectedBool: expected, atPosition: 58, forChannel: channel)
      == contradiction)
  let second = try #require(evidence.second(atLogicalPosition: 58))
  let selected = channel == .a ? second.a : second.b
  let other = channel == .a ? second.b : second.a
  #expect(selected.confidence == UInt8(confidence))
  #expect(selected.value == (belief ?? (confidence == 0 ? nil : received)))
  #expect(other == MSFEpistemicValue<Bool>())
}

@Test(
  "MSF paired observe counts zero, one or simultaneous A and B contradictions",
  arguments: [
    (Optional(MSFBits(a: false, b: false)), Bool?(false), Bool?(false), UInt8(0), 11, 11),
    (MSFBits(a: true, b: false), false, false, 1, 10, 11),
    (MSFBits(a: false, b: true), false, false, 1, 11, 10),
    (MSFBits(a: true, b: true), false, false, 2, 10, 10),
    (nil, false, false, 0, 9, 9),
    (nil, nil, false, 0, 10, 9),
    (MSFBits(a: true, b: true), nil, false, 1, 10, 10),
    (MSFBits(a: true, b: true), false, nil, 1, 10, 10),
    (MSFBits(a: true, b: true), nil, nil, 0, 10, 10),
  ])
func evidenceObserveBothChannels(
  _ received: MSFBits?, _ expectedA: Bool?, _ expectedB: Bool?,
  _ contradictions: UInt8, _ aConfidence: Int, _ bConfidence: Int
) throws {
  var evidence = seededEvidence(false, count: 10, position: 58, channel: .a)
  for _ in 0..<10 {
    evidence.observeSameLogicalValue(false, atLogicalPosition: 58, channel: .b)
  }
  #expect(
    evidence.observe(
      receivedBool: received, expectedA: expectedA, expectedB: expectedB, atPosition: 58)
      == contradictions)
  let second = try #require(evidence.second(atLogicalPosition: 58))
  #expect(second.a.value == false && second.b.value == false)
  #expect(second.a.confidence == UInt8(aConfidence))
  #expect(second.b.confidence == UInt8(bConfidence))
}

@Test(
  "MSF observe contradiction counters are per-call and fit all eighty-six channel mismatches",
  arguments: [(false, false, UInt8(0)), (true, false, 43), (true, true, 86)])
func evidenceContradictionCounterBounds(_ a: Bool, _ b: Bool, _ totalExpected: UInt8) {
  var evidence = MSFEvidenceFrame()
  for _ in 0..<255 {
    var total: UInt8 = 0
    for position in 17...59 {
      total += evidence.observe(
        receivedBool: MSFBits(a: a, b: b), expectedA: false, expectedB: false,
        atPosition: position)
    }
    #expect(total == totalExpected)
  }
  let second = evidence.second(atLogicalPosition: 17)
  #expect(second?.a.confidence == (a ? 0 : 30))
  #expect(second?.b.confidence == (b ? 0 : 30))
}

@Test(
  "MSF observe does not validate positions before reporting predicted contradictions",
  arguments: [Int.min, 16, 60, Int.max])
func evidenceObserveOutOfRange(_ position: Int) {
  var evidence = MSFEvidenceFrame()
  let mismatch = evidence.observe(
    receivedBool: true, expectedBool: false,
    atPosition: position, forChannel: .a)
  let match = evidence.observe(
    receivedBool: false, expectedBool: false,
    atPosition: position, forChannel: .a)
  #expect(mismatch)
  #expect(!match)
  #expect(
    evidence.observe(
      receivedBool: MSFBits(a: true, b: true), expectedA: false,
      expectedB: false, atPosition: position) == 2)
  for valid in 17...59 {
    #expect(evidence.second(atLogicalPosition: valid) == MSFEpistemicSecond())
  }
}

@Test("MSF matching valid parity groups restore exactly their A data and B parity evidence")
func evidenceRestoreAllGroups() throws {
  var evidence = MSFEvidenceFrame()
  #expect(
    evidence.restoreValidatedGroups(
      fromLogicalFrame: try evidenceLogicalFrame(), matching: evidencePrediction()) == 4)
  for position in 17...59 {
    let second = try #require(evidence.second(atLogicalPosition: position))
    if position <= 51 {
      let received = UInt64(0x132_694b_c27e) & (UInt64(1) << (59 - position)) != 0
      #expect(second.a.value == received && second.a.confidence == 30)
    } else {
      #expect(second.a == MSFEpistemicValue<Bool>())
    }
    if (54...57).contains(position) {
      #expect(second.b.value == (position == 57) && second.b.confidence == 30)
    } else {
      #expect(second.b == MSFEpistemicValue<Bool>())
    }
  }
  #expect(
    evidence.restoreValidatedGroups(
      fromLogicalFrame: try evidenceLogicalFrame(), matching: evidencePrediction()) == 4)
}

@Test(
  "MSF invalid or indeterminate parity groups preserve prior evidence while other groups restore",
  arguments: [
    (17...24, 54, 17), (25...35, 55, 25), (36...38, 56, 36), (39...51, 57, 39),
  ], [false, true])
func evidenceRestorePartialGroups(_ sample: (ClosedRange<Int>, Int, Int), _ unknown: Bool) throws {
  let (positions, parity, damagedPosition) = sample
  let mask = UInt64(1) << (59 - damagedPosition)
  let logical = try evidenceLogicalFrame(aFlip: unknown ? 0 : mask, unknown: unknown ? mask : 0)
  var evidence = MSFEvidenceFrame(confirmed: evidencePrediction())
  evidence.agePredictableBits(in: evidencePrediction())
  #expect(
    evidence.restoreValidatedGroups(fromLogicalFrame: logical, matching: evidencePrediction())
      == 3)
  for position in 17...51 {
    #expect(
      evidence.second(atLogicalPosition: position)?.a.confidence
        == (positions.contains(position) ? 29 : 30))
  }
  for position in 54...57 {
    #expect(
      evidence.second(atLogicalPosition: position)?.b.confidence
        == (position == parity ? 29 : 30))
  }
  #expect(evidence.second(atLogicalPosition: 58)?.b.confidence == 29)
}

@Test(
  "MSF structurally valid groups must also match predictions before restoring confidence",
  arguments: [
    (UInt64(1 << 42), UInt64(1 << 5), 17...24, 54),
    (UInt64(1 << 34), UInt64(1 << 4), 25...35, 55),
    (UInt64(1 << 23), UInt64(1 << 3), 36...38, 56),
    (UInt64(1 << 20), UInt64(1 << 2), 39...51, 57),
    (UInt64((1 << 42) | (1 << 41)), UInt64(0), 17...24, 54),
  ])
func evidenceRestoreMismatchedGroups(
  _ aFlip: UInt64, _ bFlip: UInt64,
  _ positions: ClosedRange<Int>, _ parity: Int
) throws {
  var evidence = MSFEvidenceFrame(confirmed: evidencePrediction())
  evidence.agePredictableBits(in: evidencePrediction())
  let logical = try evidenceLogicalFrame(aFlip: aFlip, bFlip: bFlip)
  #expect(logical.analyze().yearParity == .valid)
  #expect(logical.analyze().monthDayParity == .valid)
  #expect(logical.analyze().dayOfWeekParity == .valid)
  #expect(logical.analyze().hourMinuteParity == .valid)
  #expect(
    evidence.restoreValidatedGroups(fromLogicalFrame: logical, matching: evidencePrediction())
      == 3)
  for position in positions {
    #expect(evidence.second(atLogicalPosition: position)?.a.confidence == 29)
  }
  #expect(evidence.second(atLogicalPosition: parity)?.b.confidence == 29)
}

@Test("MSF group restoration is independent of identifier and Summer Time validation")
func evidenceRestoreScope() throws {
  var evidence = MSFEvidenceFrame()
  let logical = try evidenceLogicalFrame(aFlip: 1, unknown: 2)
  #expect(logical.analyze().fixedIdentifier == .indeterminate)
  #expect(
    evidence.restoreValidatedGroups(fromLogicalFrame: logical, matching: evidencePrediction())
      == 4)
  #expect(evidence.second(atLogicalPosition: 58) == MSFEpistemicSecond())
  #expect(evidence.second(atLogicalPosition: 59) == MSFEpistemicSecond())
}

@Test("MSF wholly unknown parity groups do not restore or degrade existing evidence")
func evidenceRestoreUnknownGroups() throws {
  var evidence = MSFEvidenceFrame(confirmed: evidencePrediction())
  evidence.agePredictableBits(in: evidencePrediction())
  #expect(
    evidence.restoreValidatedGroups(
      fromLogicalFrame: try evidenceLogicalFrame(unknown: 0x7ff_ffff_ffff),
      matching: evidencePrediction()) == 0)
  for position in 17...59 {
    #expect(evidence.second(atLogicalPosition: position)?.a.confidence == 29)
  }
  #expect(evidence.second(atLogicalPosition: 54)?.b.confidence == 29)
}

@Test(
  "MSF paired observe ages confidence one to zero and then seeds and saturates afresh",
  arguments: [false, true])
func evidenceObserveConfidenceBoundaries(_ value: Bool) throws {
  var evidence = seededEvidence(value, count: 1, position: 58, channel: .a)
  evidence.observeSameLogicalValue(!value, atLogicalPosition: 58, channel: .b)
  #expect(
    evidence.observe(receivedBool: nil, expectedA: value, expectedB: !value, atPosition: 58)
      == 0)
  #expect(evidence.second(atLogicalPosition: 58) == MSFEpistemicSecond())
  #expect(
    evidence.observe(receivedBool: nil, expectedA: value, expectedB: !value, atPosition: 58)
      == 0)
  #expect(evidence.second(atLogicalPosition: 58) == MSFEpistemicSecond())
  let received = MSFBits(a: !value, b: value)
  #expect(
    evidence.observe(
      receivedBool: received, expectedA: !value, expectedB: value, atPosition: 58) == 0)
  let seeded = try #require(evidence.second(atLogicalPosition: 58))
  #expect(seeded.a.value == !value && seeded.b.value == value)
  #expect(seeded.a.confidence == 1 && seeded.b.confidence == 1)
  for _ in 0..<255 {
    #expect(
      evidence.observe(
        receivedBool: received, expectedA: !value, expectedB: value, atPosition: 58) == 0)
  }
  let saturated = try #require(evidence.second(atLogicalPosition: 58))
  #expect(saturated.a.value == !value && saturated.b.value == value)
  #expect(saturated.a.confidence == 30 && saturated.b.confidence == 30)
}

@Test(
  "MSF unknown parity positions give restoration counts from zero through four",
  arguments: [
    (UInt64(0x00), UInt8(4)), (0x20, 3), (0x30, 2), (0x38, 1), (0x3c, 0),
  ])
func evidenceRestoreCounterBoundaries(_ unknown: UInt64, _ count: UInt8) throws {
  // Packed bits 5, 4, 3, 2 are B54, B55, B56, B57. Unknown flags
  // remove the A/B pair at each position, independently of its data group.
  var evidence = MSFEvidenceFrame(confirmed: evidencePrediction())
  for _ in 0..<19 { evidence.agePredictableBits(in: evidencePrediction()) }
  #expect(
    evidence.restoreValidatedGroups(
      fromLogicalFrame: try evidenceLogicalFrame(unknown: unknown),
      matching: evidencePrediction()) == count)
  for (positions, parity, mask) in [
    (17...24, 54, UInt64(0x20)), (25...35, 55, 0x10),
    (36...38, 56, 0x08), (39...51, 57, 0x04),
  ] {
    let confidence: UInt8 = unknown & mask == 0 ? 30 : 11
    for position in positions {
      #expect(evidence.second(atLogicalPosition: position)?.a.confidence == confidence)
    }
    #expect(evidence.second(atLogicalPosition: parity)?.b.confidence == confidence)
  }
  #expect(evidence.second(atLogicalPosition: 58)?.b.confidence == 11)
}

private func seededEvidence(
  _ value: Bool?, count: Int, position: Int, channel: MSFChannel
)
  -> MSFEvidenceFrame
{
  var evidence = MSFEvidenceFrame()
  if let value {
    for _ in 0..<count {
      evidence.observeSameLogicalValue(value, atLogicalPosition: position, channel: channel)
    }
  }
  return evidence
}

private func evidencePrediction(
  day: Int = 29, weekday: Int = 2, hour: Int = 17, minute: Int = 42,
  summerTime: Bool = true, predictSummerTime: Bool = true
) -> MSFExpectedFrame {
  MSFExpectedFrame(
    calendarDateTime: CalendarDateTimeComponents(
      year: 2026, month: 9, dayOfMonth: day, dayOfWeek: weekday,
      hour: hour, minute: minute, second: 0, timeZone: (summerTime ? .bst : .gmt)),
    predictSummerTime: predictSummerTime)
}

private func evidenceLogicalFrame(
  aFlip: UInt64 = 0, bFlip: UInt64 = 0, unknown: UInt64 = 0
)
  throws -> MSFLogicalFrame
{
  try #require(
    MSFLogicalFrame(
      completedFrame: MSFCompletedFrame(
        aBits: 0x132_694b_c27e ^ aFlip, bBits: 0x6 ^ bFlip, unknownBits: unknown,
        dataCount: 59, hasOpeningMarker: true)))
}
