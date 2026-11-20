//
//  MSFClockModelTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-13.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

private let clockStart: UInt64 = 10_000_000
private let clockMinute: UInt64 = 60_000_000
private let clockUnknownSuffix: UInt64 = 0x7ff_ffff_ffff

@Test("MSF clock starts unacquired without an anchor, snapshot or evidence")
func clockInitialState() {
  let clock = MSFClockModel()
  #expect(!clock.isAcquired)
  #expect(clock.anchorMarkerTime == nil)
  #expect(clock.currentCalendarDateTime == nil)
  #expect(clock.currentSnapshot(at: 0) == nil)
  #expect(clock.currentSnapshot(at: UInt64.max) == nil)
  for position in 17...59 {
    #expect(clock.evidence.second(atLogicalPosition: position) == MSFEpistemicSecond())
  }
}

@Test("MSF clock acquires fixed confirmed GMT and BST frames", arguments: [false, true])
func clockConfirmedAcquisition(_ summerTime: Bool) throws {
  var clock = MSFClockModel()
  // Archived independent fixture: 2026-09-29 Tuesday 17:42; only B58 changes.
  let frame = fixedClockFrame(bFlip: summerTime ? 0 : 2)
  let calendar = clockCalendar(summerTime: summerTime)
  #expect(clock.receive(completedFrame: frame) == .acquired(calendar))
  #expect(clock.isAcquired)
  #expect(clock.anchorMarkerTime == clockStart)
  #expect(clock.currentCalendarDateTime == calendar)
  let snapshot = try #require(clock.currentSnapshot(at: clockStart))
  #expect(snapshot.calendarDateTime == calendar)
  expectClockStates(snapshot.clockState, .confirmed)
  for position in 17...59 {
    let mask = UInt64(1) << (59 - position)
    let second = try #require(clock.evidence.second(atLogicalPosition: position))
    #expect(second.a.value == (frame.aBits & mask != 0))
    #expect(second.b.value == (frame.bBits & mask != 0))
    #expect(second.a.confidence == 30)
    #expect(second.b.confidence == 30)
  }
}

@Test(
  "MSF clock accepts confirmed frames at zero and large hardware timestamps",
  arguments: [UInt64(0), clockStart, UInt64.max - 120_000_000])
func clockAcquisitionTimestamp(_ timestamp: UInt64) throws {
  let clock = acquiredClock(at: timestamp)
  #expect(clock.anchorMarkerTime == timestamp)
  let snapshot = try #require(clock.currentSnapshot(at: timestamp + 60_000_000))
  #expect(snapshot.calendarDateTime == clockCalendar(minute: 43))
}

@Test(
  "MSF clock cannot initially acquire empty, incomplete or damaged frames",
  arguments: [
    (UInt64(0), 0, UInt64(0), UInt64(0)),
    (0, 42, 0, 0), (0, 57, 0, 0), (1, 59, 0, 0),
    (0, 59, 1, 0), (0, 59, 0, 1 << 5), (0, 59, 1 << 42, 1 << 5),
  ])
func clockUnacquiredReception(_ unknown: UInt64, _ count: Int, _ aFlip: UInt64, _ bFlip: UInt64) {
  var clock = MSFClockModel()
  let before = clock
  #expect(
    clock.receive(
      completedFrame: fixedClockFrame(
        unknown: unknown, dataCount: count, aFlip: aFlip, bFlip: bFlip)) == .unacquired)
  expectClockUnchanged(before, clock)
  #expect(clock.receive(completedFrame: fixedClockFrame()) == .acquired(clockCalendar()))
}

@Test("MSF clock acquires a valid markerless suffix")
func clockMarkerlessAcquisition() {
  var clock = MSFClockModel()
  let frame = MSFCompletedFrame(
    aBits: 0x132_694b_c27e, bBits: 0x6, dataCount: 43,
    hasOpeningMarker: false, closingMarkerTime: clockStart)
  #expect(clock.receive(completedFrame: frame) == .acquired(clockCalendar()))
  #expect(clock.anchorMarkerTime == clockStart)
}

@Test(
  "MSF clock accepts a supported partial handoff without inventing confirmation",
  arguments: [Optional<Bool>.none, false, true])
func clockSupportedHandoff(_ summerTime: Bool?) throws {
  let supported = supportedClockInput(summerTime: summerTime)
  var clock = MSFClockModel()
  #expect(clock.start(from: supported) == .acquiredFromPartial(supported.currentCalendarDateTime))
  #expect(clock.anchorMarkerTime == clockStart)
  #expect(clock.currentCalendarDateTime == clockCalendar(minute: 44, summerTime: summerTime))
  let snapshot = try #require(clock.currentSnapshot(at: supported.lastMarkerTime + 1_000_000))
  #expect(snapshot.calendarDateTime == clockCalendar(minute: 44, second: 1, summerTime: summerTime))
  #expect(snapshot.clockState.year == .unknown)
  #expect(snapshot.clockState.minute == .candidate)
  #expect(snapshot.clockState.timeZone == (summerTime == nil ? .unknown : .candidate))
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a.value == nil)
  #expect(clock.evidence.second(atLogicalPosition: 45)?.a.confidence == 2)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.value == summerTime)
}

@Test("MSF clock refuses a second supported handoff after acquisition")
func clockRepeatedSupportedHandoff() {
  var clock = acquiredClock()
  let before = clock
  #expect(clock.start(from: supportedClockInput()) == .stale)
  expectClockUnchanged(before, clock)
}

@Test(
  "MSF clock calendar and seconds follow elapsed hardware time",
  arguments: [
    (UInt64(0), 42, 0), (999_999, 42, 0), (1_000_000, 42, 1),
    (59_999_999, 42, 59), (60_000_000, 43, 0), (60_999_999, 43, 0),
    (125_000_000, 44, 5), (185_000_000, 45, 5),
  ])
func clockElapsedProgression(_ elapsed: UInt64, _ minute: Int, _ second: Int) throws {
  let clock = acquiredClock()
  let snapshot = try #require(clock.currentSnapshot(at: clockStart + elapsed))
  #expect(snapshot.calendarDateTime == clockCalendar(minute: minute, second: second))
  #expect(clock.currentCalendarDateTime == clockCalendar())
  #expect(clock.anchorMarkerTime == clockStart)
}

@Test(
  "MSF clock projects explicit calendar boundaries without radio reception",
  arguments: [
    (clockCalendar(), clockCalendar(minute: 43), UInt64(1)),
    (clockCalendar(minute: 59), clockCalendar(hour: 18, minute: 0), 1),
    (
      clockCalendar(hour: 23, minute: 59),
      clockCalendar(day: 30, weekday: 3, hour: 0, minute: 0), 1
    ),
    (
      clockCalendar(month: 10, day: 3, weekday: 6, hour: 23, minute: 59),
      clockCalendar(month: 10, day: 4, weekday: 0, hour: 0, minute: 0), 1
    ),
    (
      clockCalendar(day: 30, weekday: 3, hour: 23, minute: 59),
      clockCalendar(month: 10, day: 1, weekday: 4, hour: 0, minute: 0), 1
    ),
    (
      clockCalendar(month: 10, day: 31, weekday: 6, hour: 23, minute: 59),
      clockCalendar(month: 11, day: 1, weekday: 0, hour: 0, minute: 0), 1
    ),
    (
      clockCalendar(month: 2, day: 28, weekday: 6, hour: 23, minute: 59, summerTime: false),
      clockCalendar(month: 3, day: 1, weekday: 0, hour: 0, minute: 0, summerTime: false), 1
    ),
    (
      clockCalendar(
        year: 2024, month: 2, day: 28, weekday: 3, hour: 23, minute: 59, summerTime: false),
      clockCalendar(
        year: 2024, month: 2, day: 29, weekday: 4, hour: 0, minute: 0, summerTime: false), 1
    ),
    (
      clockCalendar(
        year: 2024, month: 2, day: 29, weekday: 4, hour: 23, minute: 59, summerTime: false),
      clockCalendar(
        year: 2024, month: 3, day: 1, weekday: 5, hour: 0, minute: 0, summerTime: false), 1
    ),
    (
      clockCalendar(
        year: 2000, month: 2, day: 28, weekday: 1, hour: 23, minute: 59, summerTime: false),
      clockCalendar(
        year: 2000, month: 2, day: 29, weekday: 2, hour: 0, minute: 0, summerTime: false), 1
    ),
    (
      clockCalendar(month: 12, day: 31, weekday: 4, hour: 23, minute: 59, summerTime: false),
      clockCalendar(
        year: 2027, month: 1, day: 1, weekday: 5, hour: 0, minute: 0, summerTime: false), 1
    ),
    (clockCalendar(), clockCalendar(month: 10, day: 1, weekday: 4), 2_880),
  ])
func clockCalendarProgression(
  _ initial: CalendarDateTimeComponents, _ expected: CalendarDateTimeComponents, _ minutes: UInt64
) throws {
  var clock = MSFClockModel()
  #expect(clock.receive(completedFrame: encodedClockFrame(initial, at: clockStart)) == .acquired(initial))
  let snapshot = try #require(clock.currentSnapshot(at: clockStart + minutes * clockMinute))
  #expect(snapshot.calendarDateTime == expected)
  #expect(clock.currentCalendarDateTime == initial)
  #expect(clock.anchorMarkerTime == clockStart)
}

@Test("MSF clock snapshots neither mutate evidence nor consume observations")
func clockSnapshotNonMutation() throws {
  var clock = acquiredClock()
  let before = clock
  let first = try #require(clock.currentSnapshot(at: clockStart + 125_000_000))
  let repeated = try #require(clock.currentSnapshot(at: clockStart + 125_000_000))
  #expect(first.calendarDateTime == clockCalendar(minute: 44, second: 5))
  #expect(first.calendarDateTime == repeated.calendarDateTime)
  expectClockStates(first.clockState, .confirmed)
  _ = clock.currentSnapshot(at: clockStart + 60 * clockMinute)
  #expect(clock.currentSnapshot(at: clockStart)?.calendarDateTime == clockCalendar())
  expectClockUnchanged(before, clock)
  #expect(
    clock.receive(completedFrame: encodedClockFrame(clockCalendar(minute: 43), at: clockStart + clockMinute))
      == .corroborated(clockCalendar(minute: 43)))
}

@Test("MSF clock has no snapshot before its anchor")
func clockSnapshotBeforeAnchor() {
  let clock = acquiredClock()
  #expect(clock.currentSnapshot(at: clockStart - 1) == nil)
}

@Test(
  "MSF clock snapshot confidence crosses every band during missing reception",
  arguments: [
    (UInt64(0), EpistemicState.confirmed), (1, .confirmed), (9, .confirmed),
    (10, .supported), (19, .supported), (20, .candidate), (29, .candidate), (30, .unknown),
    (35, .unknown),
  ])
func clockProjectedConfidence(_ minutes: UInt64, _ state: EpistemicState) throws {
  let clock = acquiredClock()
  let snapshot = try #require(clock.currentSnapshot(at: clockStart + minutes * clockMinute))
  expectClockStates(snapshot.clockState, state)
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a.confidence == 30)
  #expect(clock.evidence.second(atLogicalPosition: 17)?.b.confidence == 30)
}

@Test(
  "MSF bounded holdover and returning partial frames match minute-by-minute replay",
  arguments: [UInt64(0), 1, 29, 30, 31, 35, 360, 1_440, 4_320], [false, true])
func clockBoundedHoldoverMatchesMinuteReplay(_ missed: UInt64, _ summerTime: Bool) throws {
  let initial = clockCalendar(
    year: 2027, month: 12, day: 31, weekday: 5, hour: 23, minute: 40, summerTime: summerTime)
  var clock = MSFClockModel()
  // B17 is unmodelled, even when the authoritative frame gave it full confidence.
  let start = encodedClockFrame(initial, at: clockStart, bFlip: 1 << 42)
  #expect(clock.receive(completedFrame: start) == .acquired(initial))
  var reference = try replayMSFUnobservedMinutes(
    missed, from: initial, evidence: clock.evidence, predictSummerTime: true)
  let now = clockStart + missed * clockMinute
  let projected = try #require(clock.projectedState(at: now))
  #expect(projected.index == missed)
  #expect(projected.calendarDateTime == reference.calendar)
  #expect(clock.currentSnapshot(at: now)?.calendarDateTime == reference.calendar)
  expectMSFEvidenceEqual(projected.evidence, reference.evidence)
  #expect(projected.evidence.second(atLogicalPosition: 17)?.b.value == true)
  #expect(projected.evidence.second(atLogicalPosition: 17)?.b.confidence == 30)
  #expect(clock.currentCalendarDateTime == initial)

  let arrival = try #require(reference.calendar.advanced(byMinutes: 1))
  // Unknown year parity makes this a partial frame while leaving the year bits observable.
  let partial = encodedClockFrame(arrival, at: now + clockMinute, unknown: 1 << 5, bFlip: 1 << 42)
  let logical = try #require(partial.logicalFrame())
  let expected = MSFExpectedFrame(calendarDateTime: arrival)
  reference.evidence.projectExpectedTransition(
    fromExpectedFrame: MSFExpectedFrame(calendarDateTime: reference.calendar), toExpectedFrame: expected)
  var contradictions: UInt8 = 0
  for position in MSFLogicalFrame.logicalRange {
    contradictions += reference.evidence.observe(
      receivedBool: logical.bits(atLogicalPosition: position),
      expectedA: expected.bit(at: position, channel: .a),
      expectedB: expected.bit(at: position, channel: .b),
      atPosition: position)
  }
  let groups = reference.evidence.restoreValidatedGroups(fromLogicalFrame: logical, matching: expected)
  #expect(
    clock.receive(completedFrame: partial)
      == .updated(arrival, missedMinutes: missed, contradictions: contradictions, validatedGroups: groups))
  expectMSFEvidenceEqual(clock.evidence, reference.evidence)
  let yearBitConfidence = UInt8(min(30, max(1, 31 - Int(missed))))
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a.confidence == yearBitConfidence)
  #expect(clock.anchorMarkerTime == clockStart)

  let predicted = try #require(arrival.advanced(byMinutes: 1))
  let corrected = try #require(arrival.advanced(byMinutes: 2)).settingTimeZone(summerTime ? .gmt : .bst)
  let anchor = now + 2 * clockMinute + 300_000
  let authoritative = encodedClockFrame(corrected, at: anchor)
  #expect(
    clock.receive(completedFrame: authoritative)
      == .resynchronised(expected: predicted, received: corrected))
  #expect(clock.anchorMarkerTime == anchor)
  #expect(clock.currentSnapshot(at: anchor)?.calendarDateTime == corrected)
  let confirmed = try #require(authoritative.logicalFrame())
  expectMSFEvidenceEqual(clock.evidence, MSFEvidenceFrame(confirmed: confirmed))
}

@Test("MSF bounded holdover preserves an unknown time zone until new reception establishes it")
func clockBoundedHoldoverWithUnknownTimeZone() throws {
  let handoff = supportedClockInput()
  var clock = MSFClockModel()
  #expect(clock.start(from: handoff) == .acquiredFromPartial(handoff.currentCalendarDateTime))
  let missed: UInt64 = 1_440
  let reference = try replayMSFUnobservedMinutes(
    missed, from: handoff.currentCalendarDateTime, evidence: handoff.evidence, predictSummerTime: false)
  let now = clockStart + (handoff.minuteIndex + missed) * clockMinute
  let projected = try #require(clock.projectedState(at: now))
  #expect(projected.calendarDateTime == reference.calendar)
  #expect(projected.calendarDateTime.timeZone == nil)
  expectMSFEvidenceEqual(projected.evidence, reference.evidence)
  let arrival = try #require(reference.calendar.advanced(byMinutes: 1)).settingTimeZone(.bst)
  let event = clock.receive(
    completedFrame: encodedClockFrame(arrival, at: now + clockMinute, unknown: 1 << 42))
  guard case .updated(let calendar, let missedMinutes, _, _) = event else {
    Issue.record("Expected a partial update after the outage, got \(event)")
    return
  }
  #expect(calendar == arrival && missedMinutes == missed)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.value == true)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.confidence == 1)
  #expect(clock.anchorMarkerTime == clockStart)
}

// The previous holdover algorithm, with no confidence cap or bulk calendar advance.
func replayMSFUnobservedMinutes(
  _ minutes: UInt64, from start: CalendarDateTimeComponents, evidence initial: MSFEvidenceFrame,
  predictSummerTime: Bool, ageUnmodelledSummerTime: Bool = false
) throws -> (calendar: CalendarDateTimeComponents, evidence: MSFEvidenceFrame) {
  var calendar = start
  var evidence = initial
  for _ in 0..<minutes {
    let next = try #require(calendar.advanced(byMinutes: 1))
    let expected = MSFExpectedFrame(calendarDateTime: next, predictSummerTime: predictSummerTime)
    evidence.projectExpectedTransition(
      fromExpectedFrame: MSFExpectedFrame(calendarDateTime: calendar, predictSummerTime: predictSummerTime),
      toExpectedFrame: expected)
    evidence.agePredictableBits(in: expected)
    if ageUnmodelledSummerTime {
      evidence.observeSameLogicalValue(nil, atLogicalPosition: 58, channel: .b)
    }
    calendar = next
  }
  return (calendar, evidence)
}

func expectMSFEvidenceEqual(_ actual: MSFEvidenceFrame, _ expected: MSFEvidenceFrame) {
  for position in MSFLogicalFrame.logicalRange {
    #expect(
      actual.second(atLogicalPosition: position) == expected.second(atLogicalPosition: position),
      "Logical position \(position)")
  }
}

@Test(
  "MSF clock confirmed matching frames corroborate and reanchor even beyond partial timing tolerance",
  arguments: [Int64(-300_000), 0, 100_000, 300_000])
func clockConfirmedCorroboration(_ error: Int64) throws {
  var clock = acquiredClock()
  _ = clock.receive(
    completedFrame: encodedClockFrame(
      clockCalendar(minute: 43), at: clockStart + clockMinute, unknown: clockUnknownSuffix))
  let timestamp = UInt64(Int64(clockStart + 2 * clockMinute) + error)
  let actual = clockCalendar(minute: 44)
  #expect(clock.receive(completedFrame: encodedClockFrame(actual, at: timestamp)) == .corroborated(actual))
  #expect(clock.anchorMarkerTime == timestamp)
  #expect(clock.currentCalendarDateTime == actual)
  let snapshot = try #require(clock.currentSnapshot(at: timestamp))
  #expect(snapshot.calendarDateTime == actual)
  expectClockStates(snapshot.clockState, .confirmed)
}

@Test("MSF clock newer confirmed frames can reanchor within the same minute grid position")
func clockConfirmedSameGridPosition() {
  var clock = acquiredClock()
  #expect(clock.receive(completedFrame: fixedClockFrame(at: clockStart + 1)) == .corroborated(clockCalendar()))
  #expect(clock.anchorMarkerTime == clockStart + 1)
}

@Test("MSF clock differing authoritative calendar evidence resynchronises")
func clockConfirmedResynchronisation() throws {
  var clock = acquiredClock()
  let actual = clockCalendar(minute: 45)
  let timestamp = clockStart + 2 * clockMinute
  #expect(
    clock.receive(completedFrame: encodedClockFrame(actual, at: timestamp))
      == .resynchronised(expected: clockCalendar(minute: 44), received: actual))
  #expect(clock.currentCalendarDateTime == actual)
  #expect(clock.anchorMarkerTime == timestamp)
  let snapshot = try #require(clock.currentSnapshot(at: timestamp + clockMinute))
  #expect(snapshot.calendarDateTime == clockCalendar(minute: 46))
  expectClockStates(snapshot.clockState, .confirmed)
}

@Test(
  "MSF clock rejects duplicate, older and pre-anchor frames without changing state",
  arguments: [
    UInt64(0), clockStart - 1, clockStart, clockStart + 30_000_000, clockStart + 60_000_000,
  ], [false, true])
func clockStaleReception(_ timestamp: UInt64, _ confirmed: Bool) {
  var clock = acquiredClock()
  #expect(
    clock.receive(completedFrame: encodedClockFrame(clockCalendar(minute: 43), at: clockStart + clockMinute))
      == .corroborated(clockCalendar(minute: 43)))
  let before = clock
  #expect(
    clock.receive(
      completedFrame: fixedClockFrame(at: timestamp, unknown: confirmed ? 0 : clockUnknownSuffix)) == .stale)
  expectClockUnchanged(before, clock)
}

@Test("MSF clock rejects a later partial frame on an already-consumed grid position")
func clockRepeatedGridPosition() {
  var clock = acquiredClock()
  let frame = encodedClockFrame(clockCalendar(minute: 43), at: clockStart + clockMinute, unknown: clockUnknownSuffix)
  _ = clock.receive(completedFrame: frame)
  let before = clock
  #expect(
    clock.receive(
      completedFrame: encodedClockFrame(
        clockCalendar(minute: 43), at: clockStart + clockMinute + 100_000,
        unknown: clockUnknownSuffix)) == .stale)
  expectClockUnchanged(before, clock)
}

@Test(
  "MSF clock partial frames accept the inclusive plus/minus 250 ms timing window",
  arguments: [Int64(-250_000), -249_999, -1, 0, 1, 249_999, 250_000])
func clockPartialGridTolerance(_ error: Int64) {
  var clock = acquiredClock()
  let timestamp = UInt64(Int64(clockStart + clockMinute) + error)
  #expect(
    clock.receive(
      completedFrame: encodedClockFrame(clockCalendar(minute: 43), at: timestamp, unknown: clockUnknownSuffix))
      == .updated(clockCalendar(minute: 43), missedMinutes: 0, contradictions: 0, validatedGroups: 0))
  #expect(clock.anchorMarkerTime == clockStart)
  #expect(clock.currentCalendarDateTime == clockCalendar(minute: 43))
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a.confidence == 29)
}

@Test(
  "MSF clock partial frames outside tolerance leave state unchanged",
  arguments: [Int64(-29_999_999), -300_000, -250_001, 250_001, 300_000, 29_999_999])
func clockPartialOffGrid(_ error: Int64) {
  var clock = acquiredClock()
  let before = clock
  let timestamp = UInt64(Int64(clockStart + clockMinute) + error)
  #expect(
    clock.receive(
      completedFrame: encodedClockFrame(clockCalendar(minute: 43), at: timestamp, unknown: clockUnknownSuffix))
      == .offGrid(phaseErrorUs: error))
  expectClockUnchanged(before, clock)
  #expect(
    clock.receive(
      completedFrame: encodedClockFrame(
        clockCalendar(minute: 43), at: clockStart + clockMinute, unknown: clockUnknownSuffix
      ))
      == .updated(clockCalendar(minute: 43), missedMinutes: 0, contradictions: 0, validatedGroups: 0))
}

@Test(
  "MSF clock reports nearest-grid errors with the exact halfway point rounded down",
  arguments: [
    (UInt64(90_000_000), Int64(30_000_000)), (90_000_001, -29_999_999),
  ])
func clockGridHalfway(_ elapsed: UInt64, _ error: Int64) {
  var clock = acquiredClock()
  let before = clock
  #expect(
    clock.receive(completedFrame: fixedClockFrame(at: clockStart + elapsed, unknown: clockUnknownSuffix))
      == .offGrid(phaseErrorUs: error))
  expectClockUnchanged(before, clock)
}

@Test(
  "MSF clock currently combines the next calendar minute with pre-boundary seconds after an early partial"
)
func clockEarlyPartialSnapshotBehaviour() throws {
  var clock = acquiredClock()
  let early = clockStart + clockMinute - 250_000
  _ = clock.receive(
    completedFrame: encodedClockFrame(clockCalendar(minute: 43), at: early, unknown: clockUnknownSuffix))
  let earlySnapshot = try #require(clock.currentSnapshot(at: early))
  #expect(earlySnapshot.calendarDateTime == clockCalendar(minute: 43, second: 59))
  #expect(clock.currentSnapshot(at: clockStart + clockMinute)?.calendarDateTime == clockCalendar(minute: 43))
}

@Test(
  "MSF clock empty, short and invalid-length receptions still age a running clock",
  arguments: [0, 42, 57])
func clockDamagedFrameProgression(_ count: Int) {
  var clock = acquiredClock()
  let frame = MSFCompletedFrame(
    aBits: 0, bBits: 0, unknownBits: clockUnknownSuffix, dataCount: count,
    hasOpeningMarker: true, closingMarkerTime: clockStart + clockMinute)
  #expect(
    clock.receive(completedFrame: frame)
      == .updated(clockCalendar(minute: 43), missedMinutes: 0, contradictions: 0, validatedGroups: 0))
  #expect(clock.anchorMarkerTime == clockStart)
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a.confidence == 29)
}

@Test(
  "MSF clock unknown observations age all predicted bits through each confidence band",
  arguments: [
    (1, UInt8(29), EpistemicState.confirmed), (10, 20, .supported),
    (20, 10, .candidate), (30, 0, .unknown), (35, 0, .unknown),
  ])
func clockMissingEvidence(_ count: Int, _ confidence: UInt8, _ state: EpistemicState) throws {
  var clock = acquiredClock()
  for minute in 1...count {
    _ = clock.receive(
      completedFrame: fixedClockFrame(at: clockStart + UInt64(minute) * clockMinute, unknown: clockUnknownSuffix))
  }
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a.confidence == confidence)
  #expect(clock.evidence.second(atLogicalPosition: 54)?.b.confidence == confidence)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.confidence == confidence)
  #expect(clock.evidence.second(atLogicalPosition: 17)?.b.confidence == 30)
  let snapshot = try #require(clock.currentSnapshot(at: clockStart + UInt64(count) * clockMinute))
  expectClockStates(snapshot.clockState, state)
  #expect(snapshot.hasAcquiredTime && snapshot.hasHour && snapshot.hasMinute && snapshot.hasSecondTiming)
  if confidence == 0 { #expect(clock.evidence.second(atLogicalPosition: 17)?.a.value == nil) }
}

@Test("MSF running clock uses a consistent suffix even when physical frame length is invalid")
func clockInvalidLengthKnownSuffix() {
  var clock = acquiredClock()
  let encoded = encodedClockFrame(clockCalendar(minute: 43), at: clockStart + clockMinute)
  let frame = MSFCompletedFrame(
    aBits: encoded.aBits, bBits: encoded.bBits, dataCount: 57,
    hasOpeningMarker: true, closingMarkerTime: encoded.closingMarkerTime)
  #expect(
    clock.receive(completedFrame: frame)
      == .updated(clockCalendar(minute: 43), missedMinutes: 0, contradictions: 0, validatedGroups: 4))
  #expect(clock.anchorMarkerTime == clockStart)
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a.confidence == 30)
}

@Test("MSF clock projection and missing frames cannot seed previously unobserved evidence")
func clockUnobservedEvidenceProjection() throws {
  var clock = MSFClockModel()
  _ = clock.start(from: supportedClockInput())
  let snapshot = try #require(clock.currentSnapshot(at: clockStart + 5 * clockMinute))
  #expect(snapshot.clockState.year == .unknown)
  #expect(snapshot.clockState.timeZone == .unknown)
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a.value == nil)
  _ = clock.receive(completedFrame: fixedClockFrame(at: clockStart + 5 * clockMinute, unknown: clockUnknownSuffix))
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a.confidence == 0)
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a.value == nil)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.confidence == 0)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.value == nil)
}

@Test(
  "MSF clock reports missed minutes and projects evidence to the received minute",
  arguments: [
    (UInt64(2), UInt64(1), UInt8(28), 44), (5, 4, 25, 47),
  ])
func clockMissedMinutes(_ index: UInt64, _ missed: UInt64, _ confidence: UInt8, _ minute: Int) {
  var clock = acquiredClock()
  #expect(
    clock.receive(
      completedFrame: encodedClockFrame(
        clockCalendar(minute: minute), at: clockStart + index * clockMinute,
        unknown: clockUnknownSuffix))
      == .updated(clockCalendar(minute: minute), missedMinutes: missed, contradictions: 0, validatedGroups: 0))
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a.confidence == confidence)
  #expect(clock.evidence.second(atLogicalPosition: 51)?.a.value == (minute % 2 == 1))
  #expect(clock.evidence.second(atLogicalPosition: 17)?.b.confidence == 30)
  #expect(clock.anchorMarkerTime == clockStart)
}

@Test("MSF clock matching partial observations reinforce only once before structural validation")
func clockIndividualReinforcement() {
  var clock = acquiredClock()
  for minute in 1...5 {
    _ = clock.receive(
      completedFrame: fixedClockFrame(at: clockStart + UInt64(minute) * clockMinute, unknown: clockUnknownSuffix))
  }
  let event = clock.receive(
    completedFrame: encodedClockFrame(
      clockCalendar(minute: 48), at: clockStart + 6 * clockMinute,
      unknown: (1 << 5) | (1 << 14)))
  #expect(event == .updated(clockCalendar(minute: 48), missedMinutes: 0, contradictions: 0, validatedGroups: 2))
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a.confidence == 26)
  #expect(clock.evidence.second(atLogicalPosition: 54)?.b.confidence == 24)
  #expect(clock.evidence.second(atLogicalPosition: 45)?.a.confidence == 24)
}

@Test(
  "MSF clock parity validation restores matching groups but not invalid or indeterminate groups",
  arguments: [
    (UInt64(1) << 14, UInt64(0), UInt8(30), UInt8(30), UInt8(3)),
    ((UInt64(1) << 14) | (UInt64(1) << 5), 0, 26, 24, 2),
    (UInt64(1) << 14, UInt64(1) << 5, 26, 25, 2),
  ])
func clockParityConfidence(
  _ unknown: UInt64, _ bFlip: UInt64, _ aConfidence: UInt8, _ bConfidence: UInt8, _ groups: UInt8
) {
  var clock = acquiredClock()
  for minute in 1...5 {
    _ = clock.receive(
      completedFrame: fixedClockFrame(at: clockStart + UInt64(minute) * clockMinute, unknown: clockUnknownSuffix))
  }
  #expect(
    clock.receive(
      completedFrame: encodedClockFrame(
        clockCalendar(minute: 48), at: clockStart + 6 * clockMinute, unknown: unknown,
        bFlip: bFlip))
      == .updated(
        clockCalendar(minute: 48), missedMinutes: 0, contradictions: bFlip == 0 ? 0 : 1,
        validatedGroups: groups))
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a.confidence == aConfidence)
  #expect(clock.evidence.second(atLogicalPosition: 54)?.b.confidence == bConfidence)
}

@Test(
  "MSF clock counts contradictions on A, B and both channels of one position",
  arguments: [
    (UInt64(1) << 42, UInt64(0), UInt8(1)),
    (0, UInt64(1) << 5, 1), (UInt64(1) << 5, UInt64(1) << 5, 2),
    ((UInt64(1) << 42) | (UInt64(1) << 5), (UInt64(1) << 5) | (UInt64(1) << 2), 4),
  ])
func clockContradictionCounting(_ aFlip: UInt64, _ bFlip: UInt64, _ contradictions: UInt8) {
  var clock = acquiredClock()
  let beforeYear = clock.evidence.second(atLogicalPosition: 17)?.a
  let beforeParity = clock.evidence.second(atLogicalPosition: 54)?.b
  let event = clock.receive(
    completedFrame: encodedClockFrame(
      clockCalendar(minute: 43), at: clockStart + clockMinute,
      unknown: 1 << 14, aFlip: aFlip, bFlip: bFlip))
  guard case .updated(let calendar, let missed, let count, _) = event else {
    Issue.record("Expected a partial clock update")
    return
  }
  #expect(calendar == clockCalendar(minute: 43))
  #expect(missed == 0)
  #expect(count == contradictions)
  #expect(clock.evidence.second(atLogicalPosition: 17)?.a == beforeYear)
  #expect(clock.evidence.second(atLogicalPosition: 54)?.b == beforeParity)
  #expect(clock.anchorMarkerTime == clockStart)
}

@Test(
  "MSF clock preserves unmodelled B evidence despite received differences or absence",
  arguments: [17, 25, 52, 53, 59])
func clockUnmodelledEvidence(_ position: Int) {
  var clock = acquiredClock()
  let before = clock.evidence.second(atLogicalPosition: position)?.b
  let event = clock.receive(
    completedFrame: encodedClockFrame(
      clockCalendar(minute: 43), at: clockStart + clockMinute,
      unknown: 1 << 14, bFlip: UInt64(1) << (59 - position)))
  guard case .updated(_, _, let contradictions, _) = event else {
    Issue.record("Expected a partial clock update")
    return
  }
  #expect(contradictions == 0)
  #expect(clock.evidence.second(atLogicalPosition: position)?.b == before)
  _ = clock.receive(completedFrame: fixedClockFrame(at: clockStart + 2 * clockMinute, unknown: clockUnknownSuffix))
  #expect(clock.evidence.second(atLogicalPosition: position)?.b == before)
}

@Test(
  "MSF clock keeps unknown expected Summer Time unmodelled despite untrusted received B58",
  arguments: [false, true])
func clockUnknownSummerTimeComparison(_ observed: Bool) throws {
  var clock = MSFClockModel()
  _ = clock.start(from: supportedClockInput())
  let event = clock.receive(
    completedFrame: encodedClockFrame(
      clockCalendar(minute: 45, summerTime: observed), at: clockStart + 3 * clockMinute,
      unknown: 1 << 7))
  #expect(
    event
      == .updated(
        clockCalendar(minute: 45, summerTime: nil),
        missedMinutes: 0, contradictions: 0, validatedGroups: 4))
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.value == nil)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.confidence == 0)
  let snapshot = try #require(clock.currentSnapshot(at: clockStart + 3 * clockMinute))
  #expect(snapshot.clockState.timeZone == .unknown)
  #expect(snapshot.calendarDateTime.timeZone == nil)
}

@Test("MSF clock learns trusted partial GMT and BST without reanchoring", arguments: [false, true])
func clockLearnsSummerTime(_ observed: Bool) throws {
  var clock = MSFClockModel()
  _ = clock.start(from: supportedClockInput())
  let actual = clockCalendar(minute: 45, summerTime: observed)
  #expect(
    clock.receive(completedFrame: encodedClockFrame(actual, at: clockStart + 3 * clockMinute, unknown: 1 << 42))
      == .updated(actual, missedMinutes: 0, contradictions: 0, validatedGroups: 3))
  #expect(clock.anchorMarkerTime == clockStart)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.value == observed)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.confidence == 1)
  #expect(clock.currentSnapshot(at: clockStart + 3 * clockMinute)?.clockState.timeZone == .candidate)
  let complete = clockCalendar(minute: 46, summerTime: observed)
  #expect(
    clock.receive(completedFrame: encodedClockFrame(complete, at: clockStart + 4 * clockMinute))
      == .corroborated(complete))
}

@Test(
  "MSF clock B58 confidence accumulates once per matching partial frame and saturates",
  arguments: [
    (1, UInt8(1), EpistemicState.candidate), (2, 2, .candidate), (10, 10, .candidate),
    (11, 11, .supported), (20, 20, .supported), (21, 21, .confirmed), (30, 30, .confirmed),
    (35, 30, .confirmed),
  ])
func clockSummerTimeAccumulation(_ count: Int, _ confidence: UInt8, _ state: EpistemicState) {
  var clock = MSFClockModel()
  _ = clock.start(from: supportedClockInput())
  for offset in 1...count {
    let minuteOfHour = 44 + offset
    let calendar = clockCalendar(hour: 17 + minuteOfHour / 60, minute: minuteOfHour % 60)
    _ = clock.receive(
      completedFrame: encodedClockFrame(
        calendar, at: clockStart + UInt64(2 + offset) * clockMinute, unknown: 1 << 42))
  }
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.value == true)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.confidence == confidence)
  #expect(clock.currentSnapshot(at: clockStart + UInt64(2 + count) * clockMinute)?.clockState.timeZone == state)
  #expect(clock.anchorMarkerTime == clockStart)
}

@Test(
  "MSF clock previously unknown Summer Time does not cause false authoritative resynchronisation",
  arguments: [false, true])
func clockUnknownSummerTimeCorroboration(_ observed: Bool) {
  var clock = MSFClockModel()
  _ = clock.start(from: supportedClockInput())
  let actual = clockCalendar(minute: 45, summerTime: observed)
  #expect(
    clock.receive(completedFrame: encodedClockFrame(actual, at: clockStart + 3 * clockMinute))
      == .corroborated(actual))
  #expect(clock.anchorMarkerTime == clockStart + 3 * clockMinute)
  #expect(clock.currentCalendarDateTime == actual)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.confidence == 30)
}

@Test(
  "MSF clock known partial Summer Time contradictions preserve its value",
  arguments: [false, true])
func clockSummerTimeContradiction(_ current: Bool) {
  var clock = MSFClockModel()
  _ = clock.receive(completedFrame: fixedClockFrame(bFlip: current ? 0 : 2))
  let expected = clockCalendar(minute: 43, summerTime: current)
  #expect(
    clock.receive(
      completedFrame: encodedClockFrame(
        clockCalendar(minute: 43, summerTime: !current), at: clockStart + clockMinute,
        unknown: 1 << 42))
      == .updated(expected, missedMinutes: 0, contradictions: 1, validatedGroups: 3))
  #expect(clock.currentCalendarDateTime == expected)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.value == current)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.confidence == 30)
  #expect(clock.anchorMarkerTime == clockStart)
}

@Test(
  "MSF clock authoritative GMT/BST changes resynchronise and replace evidence",
  arguments: [false, true])
func clockAuthoritativeSummerTimeChange(_ initial: Bool) throws {
  var clock = MSFClockModel()
  _ = clock.receive(completedFrame: fixedClockFrame(bFlip: initial ? 0 : 2))
  let expected = clockCalendar(minute: 43, summerTime: initial)
  let actual = clockCalendar(minute: 43, summerTime: !initial)
  let timestamp = clockStart + clockMinute
  #expect(
    clock.receive(completedFrame: encodedClockFrame(actual, at: timestamp))
      == .resynchronised(expected: expected, received: actual))
  #expect(clock.anchorMarkerTime == timestamp)
  #expect(clock.currentCalendarDateTime == actual)
  let snapshot = try #require(clock.currentSnapshot(at: timestamp))
  #expect(snapshot.calendarDateTime.timeZone == (!initial ? .bst : .gmt))
  #expect(snapshot.clockState.timeZone == .confirmed)
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.value == !initial)
}

@Test(
  "MSF clock authoritative Summer Time frames can jump forward or repeat an hour",
  arguments: [
    (
      clockCalendar(month: 3, day: 29, weekday: 0, hour: 0, minute: 59, summerTime: false),
      clockCalendar(month: 3, day: 29, weekday: 0, hour: 1, minute: 0, summerTime: false),
      clockCalendar(month: 3, day: 29, weekday: 0, hour: 2, minute: 0, summerTime: true),
      clockCalendar(month: 3, day: 29, weekday: 0, hour: 2, minute: 1, summerTime: true)
    ),
    (
      clockCalendar(month: 10, day: 25, weekday: 0, hour: 1, minute: 59, summerTime: true),
      clockCalendar(month: 10, day: 25, weekday: 0, hour: 2, minute: 0, summerTime: true),
      clockCalendar(month: 10, day: 25, weekday: 0, hour: 1, minute: 0, summerTime: false),
      clockCalendar(month: 10, day: 25, weekday: 0, hour: 1, minute: 1, summerTime: false)
    ),
  ])
func clockSummerTimeHourDiscontinuity(
  _ initial: CalendarDateTimeComponents, _ predicted: CalendarDateTimeComponents,
  _ actual: CalendarDateTimeComponents, _ next: CalendarDateTimeComponents
) throws {
  var clock = MSFClockModel()
  #expect(clock.receive(completedFrame: encodedClockFrame(initial, at: clockStart)) == .acquired(initial))
  let timestamp = clockStart + clockMinute
  #expect(
    clock.receive(completedFrame: encodedClockFrame(actual, at: timestamp))
      == .resynchronised(expected: predicted, received: actual))
  #expect(clock.anchorMarkerTime == timestamp)
  let snapshot = try #require(clock.currentSnapshot(at: timestamp + clockMinute))
  #expect(snapshot.calendarDateTime == next)
  #expect(snapshot.clockState.timeZone == .confirmed)
}

@Test("MSF clock keeps a learned Summer Time hypothesis after its evidence ages away")
func clockAgedSummerTimeHypothesis() {
  var clock = acquiredClock()
  _ = clock.receive(completedFrame: fixedClockFrame(at: clockStart + 30 * clockMinute, unknown: clockUnknownSuffix))
  #expect(clock.evidence.second(atLogicalPosition: 58)?.b.value == nil)
  #expect(clock.currentCalendarDateTime?.timeZone == .bst)
  let actual = clockCalendar(hour: 18, minute: 13, summerTime: false)
  let expected = clockCalendar(hour: 18, minute: 13, summerTime: true)
  #expect(
    clock.receive(completedFrame: encodedClockFrame(actual, at: clockStart + 31 * clockMinute))
      == .resynchronised(expected: expected, received: actual))
}

private func clockCalendar(
  year: Int = 2026, month: Int = 9, day: Int = 29, weekday: Int = 2,
  hour: Int = 17, minute: Int = 42, second: Int = 0, summerTime: Bool? = true
) -> CalendarDateTimeComponents {
  CalendarDateTimeComponents(
    year: year, month: month, dayOfMonth: day, dayOfWeek: weekday,
    hour: hour, minute: minute, second: second, timeZone: summerTime.map { $0 ? .bst : .gmt })
}

private func fixedClockFrame(
  at timestamp: UInt64 = clockStart, unknown: UInt64 = 0, dataCount: Int = 59,
  aFlip: UInt64 = 0, bFlip: UInt64 = 0
) -> MSFCompletedFrame {
  MSFCompletedFrame(
    aBits: 0x132_694b_c27e ^ aFlip, bBits: 0x6 ^ bFlip,
    unknownBits: unknown, dataCount: dataCount, hasOpeningMarker: true,
    closingMarkerTime: timestamp)
}

private func acquiredClock(at timestamp: UInt64 = clockStart) -> MSFClockModel {
  var clock = MSFClockModel()
  #expect(clock.receive(completedFrame: fixedClockFrame(at: timestamp)) == .acquired(clockCalendar()))
  return clock
}

private func encodedClockFrame(
  _ calendar: CalendarDateTimeComponents, at timestamp: UInt64,
  unknown: UInt64 = 0, aFlip: UInt64 = 0, bFlip: UInt64 = 0
) -> MSFCompletedFrame {
  // The encoder already has independent protocol tests.
  let expected = MSFExpectedFrame(calendarDateTime: calendar)
  var a: UInt64 = 0
  var b: UInt64 = 0
  for position in 17...59 {
    let mask = UInt64(1) << (59 - position)
    if expected.bit(at: position, channel: .a) == true { a |= mask }
    if expected.bit(at: position, channel: .b) == true { b |= mask }
  }
  return MSFCompletedFrame(
    aBits: a ^ aFlip, bBits: b ^ bFlip,
    unknownBits: unknown, dataCount: 59, hasOpeningMarker: true, closingMarkerTime: timestamp)
}

private func supportedClockInput(summerTime: Bool? = nil) -> MSFSupportedAcquisition {
  // Exercise the real handoff value and evidence API, without modelling the
  // acquisition search. Two observations leave one year bit unobserved.
  var evidence = MSFEvidenceFrame()
  for _ in 0..<2 {
    for position in 18...59 {
      let mask = UInt64(1) << (59 - position)
      evidence.observeSameLogicalValue(0x132_694b_c47e & mask != 0, atLogicalPosition: position, channel: .a)
    }
    evidence.observeSameLogicalValue(summerTime, atLogicalPosition: 58, channel: .b)
  }
  return MSFSupportedAcquisition(
    anchorCalendarDateTime: clockCalendar(summerTime: summerTime),
    anchorMarkerTime: clockStart,
    currentCalendarDateTime: clockCalendar(minute: 44, summerTime: summerTime),
    minuteIndex: 2, lastMarkerTime: clockStart + 2 * clockMinute + 100_000,
    evidence: evidence, summerTime: summerTime)
}

private func expectClockStates(_ state: ClockState, _ expected: EpistemicState) {
  #expect(state.year == expected)
  #expect(state.month == expected)
  #expect(state.dayOfMonth == expected)
  #expect(state.dayOfWeek == expected)
  #expect(state.hour == expected)
  #expect(state.minute == expected)
  #expect(state.timeZone == expected)
}

private func expectClockUnchanged(_ before: MSFClockModel, _ after: MSFClockModel) {
  #expect(after.isAcquired == before.isAcquired)
  #expect(after.anchorMarkerTime == before.anchorMarkerTime)
  #expect(after.currentCalendarDateTime == before.currentCalendarDateTime)
  for position in 17...59 {
    #expect(
      after.evidence.second(atLogicalPosition: position)
        == before.evidence.second(atLogicalPosition: position))
  }
  #expect(
    after.currentSnapshot(at: clockStart + 5 * clockMinute)?.calendarDateTime
      == before.currentSnapshot(at: clockStart + 5 * clockMinute)?.calendarDateTime)
}

@Test(
  "Snapshot fractional seconds follow the model anchor across minute boundaries",
  arguments: [
    (UInt64(0), 0, UInt32(0)), (999_999, 0, 999_999),
    (1_000_000, 1, 0), (59_999_999, 59, 999_999),
    (60_000_000, 0, 0), (60_123_456, 0, 123_456), (3_600_500_000, 0, 500_000),
  ])
func clockFractionalSeconds(_ elapsed: UInt64, _ second: Int, _ fraction: UInt32) throws {
  // Deliberately not aligned to a boot-time second boundary.
  let anchor: UInt64 = 10_123_456
  let clock = acquiredClock(at: anchor)
  let snapshot = try #require(clock.currentSnapshot(at: anchor + elapsed))
  #expect(snapshot.calendarDateTime.second == second)
  #expect(snapshot.hasSecondTiming)
  #expect(snapshot.subsecondMicroseconds == fraction)
  #expect(clock.currentSnapshot(at: anchor - 1) == nil)
}

@Test(
  "Only accepted model acquisition supplies an acquired estimate, including supported partial handoff",
  arguments: [false, true])
func clockEstimateAvailability(_ partial: Bool) throws {
  var clock = MSFClockModel()
  #expect(clock.currentSnapshot(at: clockStart) == nil)
  #expect(!ClockSnapshot.unknown.hasAcquiredTime)
  #expect(!ClockSnapshot.unknown.hasHour && !ClockSnapshot.unknown.hasMinute)
  if partial {
    _ = clock.start(from: supportedClockInput())
  } else {
    _ = clock.receive(completedFrame: fixedClockFrame())
  }
  #expect(clock.isAcquired)
  let snapshot = try #require(clock.currentSnapshot(at: clockStart + 3 * clockMinute + 123_456))
  #expect(snapshot.hasAcquiredTime && snapshot.hasHour && snapshot.hasMinute && snapshot.hasSecondTiming)
  #expect(snapshot.calendarDateTime == clockCalendar(minute: 45, summerTime: partial ? nil : true))
  #expect(snapshot.subsecondMicroseconds == 123_456)
  if partial {
    // An accepted estimate is not a claim of fresh, fully confirmed radio data.
    #expect(snapshot.clockState.year == .unknown)
    #expect(snapshot.clockState.timeZone == .unknown)
    #expect(snapshot.clockState.hour != .confirmed && snapshot.clockState.minute != .confirmed)
  } else {
    #expect(snapshot.clockState.hour == .confirmed && snapshot.clockState.minute == .confirmed)
  }
}

@Test(
  "Acquired estimate survives missing or damaged reception and subsequent valid correction", arguments: [false, true])
func clockEstimateHoldoverAndCorrection(_ damaged: Bool) throws {
  var clock = acquiredClock()
  if damaged {
    for minute in 1...35 {
      _ = clock.receive(
        completedFrame: fixedClockFrame(
          at: clockStart + UInt64(minute) * clockMinute, unknown: clockUnknownSuffix, dataCount: 0))
    }
  }
  let held = try #require(clock.currentSnapshot(at: clockStart + 35 * clockMinute + 12_345_678))
  #expect(clock.isAcquired && clock.anchorMarkerTime == clockStart)
  #expect(held.hasAcquiredTime && held.hasHour && held.hasMinute && held.hasSecondTiming)
  #expect(held.calendarDateTime == clockCalendar(hour: 18, minute: 17, second: 12))
  #expect(held.subsecondMicroseconds == 345_678)
  expectClockStates(held.clockState, .unknown)

  let corrected = clockCalendar(hour: 9, minute: 23)
  let marker = clockStart + 36 * clockMinute + 123_456
  #expect(
    clock.receive(completedFrame: encodedClockFrame(corrected, at: marker))
      == .resynchronised(expected: clockCalendar(hour: 18, minute: 18), received: corrected))
  #expect(clock.anchorMarkerTime == marker)
  let after = try #require(clock.currentSnapshot(at: marker + 1_500_000))
  #expect(after.hasAcquiredTime && after.hasHour && after.hasMinute && after.hasSecondTiming)
  #expect(after.calendarDateTime == clockCalendar(hour: 9, minute: 23, second: 1))
  #expect(after.subsecondMicroseconds == 500_000)
  expectClockStates(after.clockState, .confirmed)
}
