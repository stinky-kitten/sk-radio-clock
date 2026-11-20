//
//  MSFClockAcquisitionTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

private let acquisitionStart: UInt64 = 10_000_000
private let acquisitionMinute: UInt64 = 60_000_000
private let acquisitionAllUnknown: UInt64 = 0x7ff_ffff_ffff

// Independent packed reference: 2026-09-30 Wednesday 14:33, BST.
// A = 26|09|30|3|14|33 in field-width BCD, then identifier 01111110.
// Odd-parity B54...B57 = 0,1,1,1; B58 = 1. Subsequent fixed minutes
// 14:34 and 14:35 change the minute byte to 34/35 and B57 to 0/1.

@Test("MSF acquisition starts empty without an anchor, evidence or supported handoff")
func acquisitionInitialState() {
  let acquisition = MSFClockAcquisition()
  #expect(acquisition.status == .unacquired)
  #expect(acquisition.hypothesisCount == 0)
  #expect(acquisition.informativeFrameCount == 0)
  #expect(acquisition.currentMinuteIndex == 0)
  #expect(acquisition.anchorMarkerTime == nil)
  #expect(!acquisition.exceedsCapacity)
  #expect(acquisition.currentHypothesis == nil)
  #expect(acquisition.supportedAcquisition() == nil)
  for index in [Int.min, -1, 0, 1, 63, 64, Int.max] {
    #expect(acquisition.hypothesis(at: index) == nil)
  }
}

@Test(
  "MSF acquisition ignores authoritative complete frames before checking their timestamps",
  arguments: [false, true])
func acquisitionConfirmedFrameBypass(_ seeded: Bool) throws {
  var acquisition = seeded ? try acquisitionCandidate() : MSFClockAcquisition()
  let before = acquisition
  #expect(
    acquisition.receive(completedFrame: fixedAcquisitionFrame(unknown: 0))
      == .ignored(.confirmedFrame))
  expectAcquisitionState(acquisition, matches: before)
  if !seeded {
    // A confirmed frame did not consume this marker timestamp.
    #expect(acquisition.receive(completedFrame: fixedAcquisitionFrame()) == .updated)
    #expect(acquisition.status == .candidate)
  }
}

@Test(
  "MSF one unique incomplete fixture establishes only a candidate",
  arguments: [UInt64(0), acquisitionStart, UInt64.max - acquisitionMinute])
func acquisitionUniqueSeed(_ timestamp: UInt64) {
  var acquisition = MSFClockAcquisition()
  #expect(acquisition.receive(completedFrame: fixedAcquisitionFrame(at: timestamp)) == .updated)
  #expect(acquisition.status == .candidate)
  #expect(acquisition.hypothesisCount == 1)
  #expect(acquisition.currentHypothesis == acquisitionCalendar(summerTime: nil))
  #expect(acquisition.anchorMarkerTime == timestamp)
  #expect(acquisition.currentMinuteIndex == 0)
  #expect(acquisition.informativeFrameCount == 1)
  #expect(acquisition.supportedAcquisition() == nil)
  #expect(acquisition.hypothesis(at: 0) == acquisition.currentHypothesis)
  for index in [-1, 1, 64, Int.max] { #expect(acquisition.hypothesis(at: index) == nil) }
}

@Test("MSF two independent fixed partial minutes establish supported time")
func acquisitionTwoFrameSupport() throws {
  var acquisition = try acquisitionCandidate()
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + acquisitionMinute, aBits: 0x132_706a_347e, bBits: 0x1a))
      == .updated)
  #expect(acquisition.status == .supported)
  #expect(acquisition.hypothesisCount == 1)
  #expect(acquisition.informativeFrameCount == 2)
  let handoff = try #require(acquisition.supportedAcquisition())
  #expect(handoff.anchorCalendarDateTime == acquisitionCalendar(summerTime: nil))
  #expect(handoff.currentCalendarDateTime == acquisitionCalendar(minute: 34, summerTime: nil))
  #expect(handoff.anchorMarkerTime == acquisitionStart)
  #expect(handoff.lastMarkerTime == acquisitionStart + acquisitionMinute)
  #expect(handoff.minuteIndex == 1)
}

@Test("MSF ambiguous minute candidates persist until a later observation distinguishes them")
func acquisitionAmbiguityAndFiltering() throws {
  var acquisition = MSFClockAcquisition()
  let unknown = acquisitionMask(45...51) | acquisitionMask(57)
  #expect(
    acquisition.receive(completedFrame: fixedAcquisitionFrame(unknown: unknown)) == .updated)
  #expect(acquisition.status == .ambiguous)
  #expect(acquisition.hypothesisCount == 60)
  #expect(acquisition.currentHypothesis == nil)
  #expect(acquisition.supportedAcquisition() == nil)
  for minute in 0...59 {
    #expect(
      (0..<60).contains {
        acquisition.hypothesis(at: $0)
          == acquisitionCalendar(minute: minute, summerTime: nil)
      })
  }
  let repeated = encodedAcquisitionFrame(
    acquisitionCalendar(minute: 34),
    at: acquisitionStart + acquisitionMinute, unknown: unknown)
  #expect(acquisition.receive(completedFrame: repeated) == .updated)
  #expect(acquisition.status == .ambiguous)
  // The original :59 candidate advances into the next hour and no longer
  // matches the received hour. The remaining minutes are :01 through :59.
  #expect(acquisition.hypothesisCount == 59)
  for minute in 1...59 {
    #expect(
      (0..<59).contains {
        acquisition.hypothesis(at: $0)
          == acquisitionCalendar(minute: minute, summerTime: nil)
      })
  }
  #expect(acquisition.informativeFrameCount == 2)
  #expect(acquisition.supportedAcquisition() == nil)
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + 2 * acquisitionMinute, aBits: 0x132_706a_357e)) == .updated)
  #expect(acquisition.status == .supported)
  #expect(acquisition.currentHypothesis == acquisitionCalendar(minute: 35, summerTime: nil))
  #expect(acquisition.informativeFrameCount == 3)
}

@Test("MSF complementary partial minutes filter advanced candidates without raw-bit merging")
func acquisitionComplementaryMinutes() throws {
  var acquisition = MSFClockAcquisition()
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        unknown: acquisitionMask(51) | acquisitionMask(57))) == .updated)
  #expect(acquisition.hypothesisCount == 2)
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + acquisitionMinute, aBits: 0x132_706a_347e, bBits: 0x1a,
        unknown: acquisitionMask(50) | acquisitionMask(57))) == .updated)
  #expect(acquisition.status == .supported)
  let handoff = try #require(acquisition.supportedAcquisition())
  #expect(handoff.currentCalendarDateTime == acquisitionCalendar(minute: 34, summerTime: nil))
  #expect(handoff.evidence.second(atLogicalPosition: 49)?.a.value == true)
  #expect(handoff.evidence.second(atLogicalPosition: 49)?.a.confidence == 2)
  #expect(handoff.evidence.second(atLogicalPosition: 50)?.a.value == nil)
  #expect(handoff.evidence.second(atLogicalPosition: 50)?.a.confidence == 0)
}

@Test("MSF noisy complementary fields converge on a coherent calendar minute")
func acquisitionNoisyConvergence() {
  var acquisition = MSFClockAcquisition()
  let unknown =
    acquisitionMask(18) | acquisitionMask(25) | acquisitionMask(30)
    | acquisitionMask(36) | acquisitionMask(39) | acquisitionMask(45)
    | acquisitionMask(51) | acquisitionMask(54...57)
  #expect(
    acquisition.receive(completedFrame: fixedAcquisitionFrame(unknown: unknown)) == .updated)
  #expect((1...64).contains(acquisition.hypothesisCount))
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + acquisitionMinute, aBits: 0x132_706a_347e, bBits: 0x1a,
        unknown: acquisitionMask(50) | acquisitionMask(57))) == .updated)
  #expect(acquisition.status == .supported)
  #expect(acquisition.currentHypothesis == acquisitionCalendar(minute: 34, summerTime: nil))
}

@Test("MSF parity-only reception filters candidates without supplying independent A-data support")
func acquisitionParityOnlyPromotion() {
  var acquisition = MSFClockAcquisition()
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        unknown: acquisitionMask(51) | acquisitionMask(57))) == .updated)
  #expect(acquisition.hypothesisCount == 2)
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + acquisitionMinute, aBits: 0x132_706a_347e, bBits: 0x1a,
        unknown: acquisitionAllUnknown & ~acquisitionMask(54...57))) == .updated)
  #expect(acquisition.hypothesisCount == 1)
  #expect(acquisition.status == .candidate)
  #expect(acquisition.informativeFrameCount == 1)
  #expect(acquisition.supportedAcquisition() == nil)
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + 2 * acquisitionMinute, aBits: 0x132_706a_357e)) == .updated)
  #expect(acquisition.status == .supported)
}

@Test("MSF exactly sixty-four legal hypotheses are retained without selecting an arbitrary winner")
func acquisitionExactCapacity() {
  var acquisition = MSFClockAcquisition()
  // Known hour BCD bit 2 selects 4...7 and 14...17 (8 hours).
  // Known minute BCD bits 5 and 1 select 22,23,26,27,32,33,36,37 (8 minutes).
  let knownTime = acquisitionMask(42) | acquisitionMask(46) | acquisitionMask(50)
  let unknown = (acquisitionMask(39...51) & ~knownTime) | acquisitionMask(57)
  #expect(
    acquisition.receive(completedFrame: fixedAcquisitionFrame(unknown: unknown)) == .updated)
  #expect(acquisition.hypothesisCount == 64)
  #expect(acquisition.status == .ambiguous)
  #expect(!acquisition.exceedsCapacity)
  for hour in [4, 5, 6, 7, 14, 15, 16, 17] {
    for minute in [22, 23, 26, 27, 32, 33, 36, 37] {
      let expected = acquisitionCalendar(hour: hour, minute: minute, summerTime: nil)
      #expect((0..<64).filter { acquisition.hypothesis(at: $0) == expected }.count == 1)
    }
  }
  #expect(acquisition.hypothesis(at: 64) == nil)
  #expect(acquisition.currentHypothesis == nil)
  #expect(acquisition.supportedAcquisition() == nil)
}

@Test(
  "MSF both overflow routes discard all candidates and permit a later clean seed",
  arguments: [
    // One date, 2 hours x 60 minutes: temporary time-domain overflow.
    acquisitionMask(44...51) | acquisitionMask(57),
    // Two years, unknown weekday, 60 minutes each: combined-domain overflow.
    acquisitionMask(24) | acquisitionMask(54) | acquisitionMask(36...38)
      | acquisitionMask(56) | acquisitionMask(45...51) | acquisitionMask(57),
    acquisitionAllUnknown & ~acquisitionMask(17),
  ])
func acquisitionCapacityOverflow(_ unknown: UInt64) {
  var acquisition = MSFClockAcquisition()
  #expect(
    acquisition.receive(completedFrame: fixedAcquisitionFrame(unknown: unknown))
      == .tooAmbiguous)
  #expect(acquisition.status == .ambiguous && acquisition.exceedsCapacity)
  #expect(acquisition.hypothesisCount == 0)
  #expect(acquisition.informativeFrameCount == 0)
  #expect(acquisition.anchorMarkerTime == nil)
  #expect(acquisition.supportedAcquisition() == nil)
  #expect(acquisition.receive(completedFrame: fixedAcquisitionFrame()) == .ignored(.staleMarker))
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + acquisitionMinute, aBits: 0x132_706a_347e, bBits: 0x1a))
      == .updated)
  #expect(acquisition.status == .candidate && !acquisition.exceedsCapacity)
  #expect(acquisition.informativeFrameCount == 1)
  #expect(acquisition.anchorMarkerTime == acquisitionStart + acquisitionMinute)
}

@Test("MSF compatible single-bit reception can support a unique calendar hypothesis")
func acquisitionSingleKnownBit() throws {
  var acquisition = try acquisitionCandidate()
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + acquisitionMinute, aBits: 0x132_706a_347e, bBits: 0x1a,
        unknown: acquisitionAllUnknown & ~acquisitionMask(51))) == .updated)
  #expect(acquisition.status == .supported)
  #expect(acquisition.informativeFrameCount == 2)
  #expect(acquisition.currentHypothesis == acquisitionCalendar(minute: 34, summerTime: nil))
}

@Test(
  "MSF indeterminate-group contradictions reset acquisition without reusing the rejected marker",
  arguments: [17, 25, 36, 39])
func acquisitionContradictionRecovery(_ unknownPosition: Int) throws {
  var acquisition = try acquisitionCandidate()
  let bad = fixedAcquisitionFrame(
    at: acquisitionStart + acquisitionMinute,
    aBits: 0x132_706a_347e ^ acquisitionMask(unknownPosition + 1), bBits: 0x1a,
    unknown: acquisitionMask(unknownPosition) | acquisitionMask(58))
  #expect(acquisition.receive(completedFrame: bad) == .reset(.incompatibleEvidence))
  #expect(acquisition.status == .unacquired)
  #expect(acquisition.hypothesisCount == 0 && acquisition.informativeFrameCount == 0)
  #expect(acquisition.anchorMarkerTime == nil && acquisition.currentMinuteIndex == 0)
  #expect(acquisition.supportedAcquisition() == nil)
  #expect(acquisition.receive(completedFrame: bad) == .ignored(.staleMarker))
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + 2 * acquisitionMinute, aBits: 0x132_706a_357e)) == .updated)
  #expect(acquisition.status == .candidate && acquisition.informativeFrameCount == 1)
}

@Test(
  "MSF acquisition progression follows explicit calendar boundaries",
  arguments: [
    (acquisitionCalendar(minute: 59), acquisitionCalendar(hour: 15, minute: 0)),
    (
      acquisitionCalendar(day: 29, weekday: 2, hour: 23, minute: 59),
      acquisitionCalendar(hour: 0, minute: 0)
    ),
    (
      acquisitionCalendar(hour: 23, minute: 59),
      acquisitionCalendar(month: 10, day: 1, weekday: 4, hour: 0, minute: 0)
    ),
    (
      acquisitionCalendar(year: 2028, month: 2, day: 28, weekday: 1, hour: 23, minute: 59),
      acquisitionCalendar(year: 2028, month: 2, day: 29, weekday: 2, hour: 0, minute: 0)
    ),
    (
      acquisitionCalendar(year: 2028, month: 2, day: 29, weekday: 2, hour: 23, minute: 59),
      acquisitionCalendar(year: 2028, month: 3, day: 1, weekday: 3, hour: 0, minute: 0)
    ),
    (
      acquisitionCalendar(year: 2026, month: 12, day: 31, weekday: 4, hour: 23, minute: 59),
      acquisitionCalendar(year: 2027, month: 1, day: 1, weekday: 5, hour: 0, minute: 0)
    ),
    (
      acquisitionCalendar(year: 2000, month: 2, day: 28, weekday: 1, hour: 23, minute: 59),
      acquisitionCalendar(year: 2000, month: 2, day: 29, weekday: 2, hour: 0, minute: 0)
    ),
  ])
func acquisitionCalendarProgression(
  _ first: CalendarDateTimeComponents, _ next: CalendarDateTimeComponents
)
  throws
{
  var acquisition = try acquisitionCandidate(first)
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        next,
        at: acquisitionStart + acquisitionMinute)) == .updated)
  #expect(acquisition.currentHypothesis == next.settingTimeZone(nil))
  let handoff = try #require(acquisition.supportedAcquisition())
  #expect(handoff.currentCalendarDateTime == next.settingTimeZone(nil))
  #expect(handoff.anchorCalendarDateTime == first.settingTimeZone(nil))
  #expect(handoff.anchorMarkerTime == acquisitionStart && handoff.minuteIndex == 1)
}

@Test(
  "MSF acquisition accepts valid calendar years at both ends of its century",
  arguments: [
    acquisitionCalendar(year: 2000, month: 1, day: 1, weekday: 6),
    acquisitionCalendar(year: 2099, month: 12, day: 31, weekday: 4),
  ])
func acquisitionCalendarCenturyBounds(_ calendar: CalendarDateTimeComponents) throws {
  let acquisition = try acquisitionCandidate(calendar)
  #expect(acquisition.currentHypothesis == calendar.settingTimeZone(nil))
}

@Test(
  "MSF missing minutes advance by recorded Pico timestamps without adding observations",
  arguments: [
    (UInt64(1), acquisitionCalendar(minute: 34)), (2, acquisitionCalendar(minute: 35)),
    (5, acquisitionCalendar(minute: 38)),
    (1_440, acquisitionCalendar(month: 10, day: 1, weekday: 4)),
  ])
func acquisitionSkippedMinutes(_ index: UInt64, _ expected: CalendarDateTimeComponents) throws {
  var acquisition = try acquisitionCandidate()
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        expected,
        at: acquisitionStart + index * acquisitionMinute)) == .updated)
  #expect(acquisition.currentHypothesis == expected.settingTimeZone(nil))
  #expect(acquisition.currentMinuteIndex == index)
  #expect(acquisition.informativeFrameCount == 2)
  #expect(acquisition.anchorMarkerTime == acquisitionStart)
}

@Test("MSF several missing minutes can cross a month boundary")
func acquisitionSkippedCalendarBoundary() throws {
  var acquisition = try acquisitionCandidate(acquisitionCalendar(hour: 23, minute: 58))
  let next = acquisitionCalendar(month: 10, day: 1, weekday: 4, hour: 0, minute: 3)
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        next,
        at: acquisitionStart + 5 * acquisitionMinute)) == .updated)
  #expect(acquisition.currentHypothesis == next.settingTimeZone(nil))
}

@Test(
  "MSF minute-grid accepts inclusive quarter-second limits and resets just outside them",
  arguments: [Int64(-250_001), -250_000, -1, 0, 1, 250_000, 250_001])
func acquisitionTimingTolerance(_ error: Int64) throws {
  var acquisition = try acquisitionCandidate()
  let timestamp = UInt64(Int64(acquisitionStart + acquisitionMinute) + error)
  let frame = fixedAcquisitionFrame(at: timestamp, aBits: 0x132_706a_347e, bBits: 0x1a)
  let event = acquisition.receive(completedFrame: frame)
  if error < -250_000 || error > 250_000 {
    #expect(event == .reset(.offGrid(phaseErrorUs: error)))
    #expect(acquisition.status == .unacquired && acquisition.anchorMarkerTime == nil)
    #expect(acquisition.receive(completedFrame: frame) == .ignored(.staleMarker))
    #expect(
      acquisition.receive(
        completedFrame: fixedAcquisitionFrame(
          at: acquisitionStart + 2 * acquisitionMinute, aBits: 0x132_706a_357e))
        == .updated)
    #expect(acquisition.status == .candidate)
  } else {
    #expect(event == .updated)
    #expect(acquisition.currentHypothesis == acquisitionCalendar(minute: 34, summerTime: nil))
    #expect(acquisition.anchorMarkerTime == acquisitionStart)
    #expect(acquisition.supportedAcquisition()?.lastMarkerTime == timestamp)
  }
}

@Test("MSF supporting marker jitter never moves the initial Pico anchor")
func acquisitionFixedAnchor() throws {
  var acquisition = try acquisitionCandidate()
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + acquisitionMinute + 200_000,
        aBits: 0x132_706a_347e, bBits: 0x1a)) == .updated)
  #expect(acquisition.anchorMarkerTime == acquisitionStart)
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + 2 * acquisitionMinute + 400_000,
        aBits: 0x132_706a_357e)) == .reset(.offGrid(phaseErrorUs: 400_000)))
}

@Test(
  "MSF duplicate, older and same-minute timestamps cannot add independent support",
  arguments: [UInt64(0), acquisitionStart - 1, acquisitionStart, acquisitionStart + 200_000])
func acquisitionStaleMarkers(_ timestamp: UInt64) throws {
  var acquisition = try acquisitionCandidate()
  let before = acquisition
  #expect(
    acquisition.receive(completedFrame: fixedAcquisitionFrame(at: timestamp))
      == .ignored(.staleMarker))
  expectAcquisitionState(acquisition, matches: before)
  #expect(acquisition.supportedAcquisition() == nil)
}

@Test(
  "MSF insufficient or invalid marked lengths are ignored before hypothesis seeding",
  arguments: [0, 1, 42, 43, 57, 61, 65])
func acquisitionRejectedLengths(_ count: Int) {
  var acquisition = MSFClockAcquisition()
  let frame = fixedAcquisitionFrame(dataCount: count)
  #expect(
    acquisition.receive(completedFrame: frame)
      == .ignored(count < 43 ? .insufficientData : .invalidFrameLength))
  #expect(acquisition.status == .unacquired && acquisition.anchorMarkerTime == nil)
  #expect(acquisition.receive(completedFrame: fixedAcquisitionFrame()) == .ignored(.staleMarker))
}

@Test(
  "MSF all physical minute lengths and markerless suffixes can seed partial acquisition",
  arguments: [(58, true), (59, true), (60, true), (43, false), (57, false), (65, false)])
func acquisitionAcceptedLengths(_ count: Int, _ opening: Bool) {
  var acquisition = MSFClockAcquisition()
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        dataCount: count, hasOpeningMarker: opening)) == .updated)
  #expect(acquisition.status == .candidate)
  #expect(acquisition.currentHypothesis == acquisitionCalendar(summerTime: nil))
}

@Test(
  "MSF rejected aligned frames consume the minute and timestamp without adding support",
  arguments: [
    MSFAcquisitionIgnore.insufficientData, .invalidFrameLength, .invalidIdentifier,
    .uninformative,
  ])
func acquisitionRejectedTimestampConsumption(_ reason: MSFAcquisitionIgnore) throws {
  var acquisition = try acquisitionCandidate()
  let timestamp = acquisitionStart + acquisitionMinute
  let frame = fixedAcquisitionFrame(
    at: timestamp, aBits: 0x132_706a_347e,
    bBits: 0x1a,
    unknown: reason == .uninformative ? acquisitionAllUnknown : acquisitionMask(58),
    aFlip: reason == .invalidIdentifier ? acquisitionMask(52) : 0,
    dataCount: reason == .insufficientData ? 42 : reason == .invalidFrameLength ? 57 : 59)
  #expect(acquisition.receive(completedFrame: frame) == .ignored(reason))
  #expect(acquisition.status == .candidate && acquisition.informativeFrameCount == 1)
  #expect(acquisition.currentMinuteIndex == 1)
  #expect(acquisition.currentHypothesis == acquisitionCalendar(minute: 34, summerTime: nil))
  #expect(
    acquisition.receive(completedFrame: fixedAcquisitionFrame(at: timestamp))
      == .ignored(.staleMarker))
  #expect(
    acquisition.receive(completedFrame: fixedAcquisitionFrame(at: timestamp + 100_000))
      == .ignored(.staleMarker))
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + 2 * acquisitionMinute, aBits: 0x132_706a_357e)) == .updated)
  #expect(acquisition.status == .supported && acquisition.informativeFrameCount == 2)
}

@Test(
  "MSF valid-parity malformed BCD and illegal calendars have no legal acquisition hypothesis",
  arguments: [
    ("malformed year", UInt64(0x152_706a_337e), UInt64(0x1e)),
    ("month zero", 0x130_306a_337e, 0x1e),
    ("month thirteen", 0x134_f06a_337e, 0x0e),
    ("malformed month", 0x132_b06a_337e, 0x1e),
    ("day zero", 0x132_406a_337e, 0x1e),
    ("September thirty-one", 0x132_716a_337e, 0x0e),
    ("ordinary February twenty-nine", 0x130_a90a_337e, 0x1e),
    ("leap February thirty", 0x140_b06a_337e, 0x2e),
    ("malformed day", 0x132_7a6a_337e, 0x1e),
    ("wrong weekday", 0x132_708a_337e, 0x16),
    ("weekday seven", 0x132_70ea_337e, 0x16),
    ("hour twenty-four", 0x132_7072_337e, 0x1e),
    ("malformed hour", 0x132_706d_337e, 0x1a),
    ("minute sixty", 0x132_706a_607e, 0x1e),
    ("malformed minute", 0x132_706a_3a7e, 0x1e),
  ])
func acquisitionInvalidCalendars(_ name: String, _ a: UInt64, _ b: UInt64) throws {
  // Literal field replacements and independently counted odd parity. Unknown
  // position 58 keeps these inputs on the partial acquisition path.
  let frame = fixedAcquisitionFrame(aBits: a, bBits: b)
  let structure = try #require(frame.logicalFrame()).analyze()
  #expect(structure.yearParity == .valid, Comment(rawValue: name))
  #expect(structure.monthDayParity == .valid)
  #expect(structure.dayOfWeekParity == .valid)
  #expect(structure.hourMinuteParity == .valid)
  var acquisition = MSFClockAcquisition()
  #expect(acquisition.receive(completedFrame: frame) == .reset(.noLegalCalendarTime))
  #expect(acquisition.hypothesisCount == 0 && acquisition.anchorMarkerTime == nil)
  #expect(acquisition.receive(completedFrame: fixedAcquisitionFrame()) == .ignored(.staleMarker))
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + acquisitionMinute, aBits: 0x132_706a_347e, bBits: 0x1a))
      == .updated)
  #expect(acquisition.status == .candidate && acquisition.informativeFrameCount == 1)
}

@Test("MSF an impossible date is rejected even when the time domain would overflow")
func acquisitionIllegalDateBeforeOverflow() {
  var acquisition = MSFClockAcquisition()
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        aBits: 0x132_716a_337e, bBits: 0x0e,
        unknown: acquisitionMask(39...51) | acquisitionMask(57)))
      == .reset(.noLegalCalendarTime))
  #expect(!acquisition.exceedsCapacity)
}

@Test(
  "MSF invalid parity excludes each damaged group without discarding independent evidence",
  arguments: [(17...24, 54), (25...35, 55), (36...38, 56), (39...51, 57)], [false, true])
func acquisitionInvalidParityGroups(_ group: (ClosedRange<Int>, Int), _ damageData: Bool) throws {
  let (positions, parity) = group
  var acquisition = try acquisitionCandidate()
  let frame = fixedAcquisitionFrame(
    at: acquisitionStart + acquisitionMinute,
    aBits: 0x132_706a_347e, bBits: 0x1a,
    aFlip: damageData ? acquisitionMask(positions.lowerBound) : 0,
    bFlip: damageData ? 0 : acquisitionMask(parity))
  #expect(acquisition.receive(completedFrame: frame) == .updated)
  #expect(acquisition.status == .supported)
  #expect(acquisition.currentHypothesis == acquisitionCalendar(minute: 34, summerTime: nil))
  let evidence = try #require(acquisition.supportedAcquisition()).evidence
  for position in 17...51 {
    #expect(
      evidence.second(atLogicalPosition: position)?.a.value
        == (UInt64(0x132_706a_347e) & acquisitionMask(position) != 0))
    #expect(
      evidence.second(atLogicalPosition: position)?.a.confidence
        == (positions.contains(position) ? 29 : 30))
  }
  for position in 54...57 {
    #expect(
      evidence.second(atLogicalPosition: position)?.b.confidence
        == (position == parity ? 29 : 30))
  }
}

@Test("MSF an invalid initial year group preserves useful fields and supplies no year confidence")
func acquisitionInitiallyCorruptGroup() throws {
  var acquisition = MSFClockAcquisition()
  #expect(
    acquisition.receive(completedFrame: fixedAcquisitionFrame(aFlip: acquisitionMask(18)))
      == .updated)
  #expect(acquisition.hypothesisCount > 1 && !acquisition.exceedsCapacity)
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + acquisitionMinute, aBits: 0x132_706a_347e, bBits: 0x1a,
        unknown: acquisitionMask(17))) == .updated)
  #expect(acquisition.status == .supported)
  let handoff = try #require(acquisition.supportedAcquisition())
  #expect(handoff.currentCalendarDateTime == acquisitionCalendar(minute: 34))
  #expect(handoff.evidence.second(atLogicalPosition: 17)?.a.value == nil)
  #expect(handoff.evidence.second(atLogicalPosition: 18)?.a.confidence == 1)
  #expect(handoff.evidence.second(atLogicalPosition: 25)?.a.confidence == 30)
}

@Test("MSF all-invalid parity groups are uninformative rather than independent support")
func acquisitionAllCorruptGroups() throws {
  let frame = fixedAcquisitionFrame(
    at: acquisitionStart + acquisitionMinute,
    aBits: 0x132_706a_347e, bBits: 0x1a, bFlip: acquisitionMask(54...57))
  var unseeded = MSFClockAcquisition()
  #expect(unseeded.receive(completedFrame: frame) == .ignored(.uninformative))
  var acquisition = try acquisitionCandidate()
  #expect(acquisition.receive(completedFrame: frame) == .ignored(.uninformative))
  #expect(acquisition.status == .candidate && acquisition.informativeFrameCount == 1)
}

@Test(
  "MSF identifier, status or reserved B bits alone cannot seed or promote acquisition",
  arguments: [
    acquisitionAllUnknown,
    acquisitionMask(17...51) | acquisitionMask(54...57),
    acquisitionAllUnknown & ~acquisitionMask(54...57),
  ])
func acquisitionUninformativeStructure(_ unknown: UInt64) throws {
  var empty = MSFClockAcquisition()
  #expect(
    empty.receive(completedFrame: fixedAcquisitionFrame(unknown: unknown))
      == .ignored(.uninformative))
  var acquisition = try acquisitionCandidate()
  let event = acquisition.receive(
    completedFrame: fixedAcquisitionFrame(
      at: acquisitionStart + acquisitionMinute, aBits: 0x132_706a_347e, bBits: 0x1a,
      unknown: unknown))
  #expect(
    event
      == (unknown == acquisitionAllUnknown & ~acquisitionMask(54...57)
        ? .updated : .ignored(.uninformative)))
  #expect(acquisition.status == .candidate && acquisition.informativeFrameCount == 1)
}

@Test(
  "MSF unknown identifier bits are allowed but known wrong bits reject the entire observation",
  arguments: [(UInt64(0), true), (acquisitionMask(53), false)])
func acquisitionPartiallyKnownIdentifier(_ aFlip: UInt64, _ accepted: Bool) throws {
  let unknown = acquisitionMask(52)
  var acquisition = MSFClockAcquisition()
  let frame = fixedAcquisitionFrame(unknown: unknown, aFlip: aFlip)
  #expect(try #require(frame.logicalFrame()).analyze().fixedIdentifier == .indeterminate)
  #expect(
    acquisition.receive(completedFrame: frame)
      == (accepted ? .updated : .ignored(.invalidIdentifier)))
  if accepted {
    #expect(acquisition.status == .candidate)
    #expect(
      acquisition.receive(
        completedFrame: fixedAcquisitionFrame(
          at: acquisitionStart + acquisitionMinute, aBits: 0x132_706a_347e, bBits: 0x1a,
          unknown: unknown)) == .updated)
    #expect(acquisition.supportedAcquisition()?.summerTime == nil)
  } else {
    #expect(acquisition.hypothesisCount == 0)
  }
}

@Test(
  "MSF reserved B positions neither constrain hypotheses nor manufacture replay evidence",
  arguments: [17, 25, 53, 59])
func acquisitionUnmodelledB(_ position: Int) throws {
  var acquisition = try acquisitionCandidate()
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + acquisitionMinute, aBits: 0x132_706a_347e, bBits: 0x1a,
        bFlip: acquisitionMask(position))) == .updated)
  #expect(acquisition.status == .supported)
  let evidence = try #require(acquisition.supportedAcquisition()).evidence
  #expect(evidence.second(atLogicalPosition: position)?.b.value == nil)
  #expect(evidence.second(atLogicalPosition: position)?.b.confidence == 0)
}

@Test(
  "MSF replay projects changing hour and minute values before aging a gap and missing reception",
  arguments: [
    (33, acquisitionCalendar(minute: 38), 49, false),
    (56, acquisitionCalendar(hour: 15, minute: 1), 44, true),
  ])
func acquisitionReplayExpectedFrames(
  _ firstMinute: Int, _ final: CalendarDateTimeComponents,
  _ position: Int, _ expectedBit: Bool
) throws {
  var acquisition = MSFClockAcquisition()
  for index in 0..<4 {
    let value = acquisitionCalendar(minute: firstMinute + index)
    #expect(
      acquisition.receive(
        completedFrame: encodedAcquisitionFrame(
          value,
          at: acquisitionStart + UInt64(index) * acquisitionMinute,
          unknown: acquisitionMask(17) | acquisitionMask(57))) == .updated)
  }
  let before = try #require(acquisition.supportedAcquisition())
  #expect(before.evidence.second(atLogicalPosition: position)?.a.confidence == 4)
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        final,
        at: acquisitionStart + 5 * acquisitionMinute,
        unknown: acquisitionMask(17) | acquisitionMask(45...51) | acquisitionMask(57)
          | acquisitionMask(39...44))) == .updated)
  let handoff = try #require(acquisition.supportedAcquisition())
  #expect(handoff.currentCalendarDateTime == final.settingTimeZone(nil))
  #expect(handoff.evidence.second(atLogicalPosition: position)?.a.value == expectedBit)
  #expect(handoff.evidence.second(atLogicalPosition: position)?.a.confidence == 2)
  #expect(handoff.evidence.second(atLogicalPosition: 25)?.a.confidence == 30)
}

@Test(
  "MSF replay ages every absent minute before applying the next retained observation",
  arguments: [(UInt64(1), UInt8(2)), (2, 1), (3, 1), (5, 1), (1_441, 1)])
func acquisitionReplayMissingMinutes(_ index: UInt64, _ confidence: UInt8) throws {
  var acquisition = try acquisitionCandidate(unknown: acquisitionMask(17))
  let next = try #require(acquisitionCalendar().advanced(byMinutes: index))
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        next,
        at: acquisitionStart + index * acquisitionMinute, unknown: acquisitionMask(17)))
      == .updated)
  let handoff = try #require(acquisition.supportedAcquisition())
  #expect(handoff.currentCalendarDateTime == next)
  #expect(handoff.evidence.second(atLogicalPosition: 18)?.a.confidence == confidence)
  #expect(handoff.evidence.second(atLogicalPosition: 58)?.b.confidence == confidence)
  #expect(handoff.evidence.second(atLogicalPosition: 58)?.b.value == true)
  #expect(handoff.evidence.second(atLogicalPosition: 17)?.a.value == nil)
  #expect(handoff.evidence.second(atLogicalPosition: 25)?.a.confidence == 30)
}

@Test(
  "MSF trailing ignored observations project and age evidence including unmodelled B58",
  arguments: [
    (UInt64(2), acquisitionCalendar(minute: 35), UInt8(29), UInt8(1), Bool?(true)),
    (3, acquisitionCalendar(minute: 36), 28, 0, false),
    (4, acquisitionCalendar(minute: 37), 27, 0, true),
    (31, acquisitionCalendar(hour: 15, minute: 4), 0, 0, nil),
    (4_321, acquisitionCalendar(month: 10, day: 3, weekday: 6, minute: 34), 0, 0, nil),
  ],
  [
    MSFAcquisitionIgnore.uninformative, .invalidIdentifier, .invalidFrameLength,
    .insufficientData,
  ])
func acquisitionReplayTrailingIgnored(
  _ sample: (UInt64, CalendarDateTimeComponents, UInt8, UInt8, Bool?),
  _ reason: MSFAcquisitionIgnore
) throws {
  let (index, final, minuteConfidence, statusConfidence, lastBit) = sample
  var acquisition = try acquisitionCandidate(unknown: acquisitionMask(17))
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        acquisitionCalendar(minute: 34),
        at: acquisitionStart + acquisitionMinute, unknown: acquisitionMask(17))) == .updated
  )
  let beforeGap = try #require(acquisition.supportedAcquisition())
  let reference = try replayMSFUnobservedMinutes(
    index - beforeGap.minuteIndex, from: beforeGap.currentCalendarDateTime,
    evidence: beforeGap.evidence, predictSummerTime: false, ageUnmodelledSummerTime: true)
  let timestamp = acquisitionStart + index * acquisitionMinute
  let rejected = fixedAcquisitionFrame(
    at: timestamp,
    unknown: reason == .uninformative ? acquisitionAllUnknown : acquisitionMask(17),
    aFlip: reason == .invalidIdentifier ? acquisitionMask(52) : 0,
    dataCount: reason == .insufficientData ? 42 : reason == .invalidFrameLength ? 57 : 59)
  #expect(acquisition.receive(completedFrame: rejected) == .ignored(reason))
  #expect(acquisition.status == .supported && acquisition.informativeFrameCount == 2)
  let handoff = try #require(acquisition.supportedAcquisition())
  let summerTime: Bool? = statusConfidence == 0 ? nil : true
  #expect(handoff.currentCalendarDateTime == final.settingTimeZone(summerTime.map { $0 ? .bst : .gmt }))
  #expect(handoff.currentCalendarDateTime.settingTimeZone(nil) == reference.calendar.settingTimeZone(nil))
  expectMSFEvidenceEqual(handoff.evidence, reference.evidence)
  #expect(handoff.anchorCalendarDateTime == acquisitionCalendar(summerTime: summerTime))
  #expect(handoff.lastMarkerTime == timestamp && handoff.minuteIndex == index)
  #expect(handoff.evidence.second(atLogicalPosition: 51)?.a.confidence == minuteConfidence)
  #expect(handoff.evidence.second(atLogicalPosition: 51)?.a.value == lastBit)
  #expect(handoff.evidence.second(atLogicalPosition: 58)?.b.confidence == statusConfidence)
  #expect(handoff.summerTime == summerTime)
  #expect(handoff.evidence.second(atLogicalPosition: 17)?.a.value == nil)
}

@Test(
  "MSF seven, eight and nine retained observations expose real history eviction",
  arguments: [(7, UInt8(24), UInt8(30)), (8, 23, 30), (9, 0, 8), (12, 0, 8)])
func acquisitionReplayHistoryEviction(
  _ count: Int, _ oldConfidence: UInt8, _ retainedConfidence: UInt8
) throws {
  var acquisition = try acquisitionCandidate()
  // Later frames cannot distinguish 2026 from 2027: year units bit 0,
  // year parity and all weekday information are absent. The first frame's
  // constraint must still select 2026 after its received evidence is evicted.
  let unknown =
    acquisitionMask(24) | acquisitionMask(54) | acquisitionMask(36...38) | acquisitionMask(56)
  var last = fixedAcquisitionFrame()
  for index in 1..<count {
    last = encodedAcquisitionFrame(
      acquisitionCalendar(minute: 33 + index),
      at: acquisitionStart + UInt64(index) * acquisitionMinute, unknown: unknown)
    #expect(acquisition.receive(completedFrame: last) == .updated)
  }
  var withoutOriginal = MSFClockAcquisition()
  #expect(withoutOriginal.receive(completedFrame: last) == .updated)
  #expect(withoutOriginal.hypothesisCount == 2)
  #expect(acquisition.hypothesisCount == 1 && acquisition.status == .supported)
  let handoff = try #require(acquisition.supportedAcquisition())
  #expect(
    handoff.currentCalendarDateTime
      == acquisitionCalendar(minute: 32 + count, summerTime: nil))
  #expect(handoff.evidence.second(atLogicalPosition: 24)?.a.confidence == oldConfidence)
  #expect(
    handoff.evidence.second(atLogicalPosition: 24)?.a.value
      == (oldConfidence == 0 ? nil : false))
  #expect(handoff.evidence.second(atLogicalPosition: 18)?.a.confidence == retainedConfidence)
  #expect(handoff.evidence.second(atLogicalPosition: 45)?.a.confidence == 30)
}

@Test(
  "MSF replay ordinary evidence is limited to retained observations rather than lifetime support",
  arguments: [(7, UInt8(7)), (8, 8), (9, 8), (35, 8)])
func acquisitionReplayConfidenceBound(_ count: Int, _ confidence: UInt8) throws {
  var acquisition = MSFClockAcquisition()
  for index in 0..<count {
    let total = 33 + index
    #expect(
      acquisition.receive(
        completedFrame: encodedAcquisitionFrame(
          acquisitionCalendar(hour: 14 + total / 60, minute: total % 60),
          at: acquisitionStart + UInt64(index) * acquisitionMinute,
          unknown: acquisitionMask(17))) == .updated)
  }
  let handoff = try #require(acquisition.supportedAcquisition())
  #expect(acquisition.informativeFrameCount == count)
  #expect(handoff.evidence.second(atLogicalPosition: 18)?.a.confidence == confidence)
  #expect(handoff.evidence.second(atLogicalPosition: 58)?.b.confidence == confidence)
  #expect(handoff.evidence.second(atLogicalPosition: 58)?.b.state == .candidate)
  #expect(handoff.evidence.second(atLogicalPosition: 17)?.a.value == nil)
  #expect(handoff.evidence.second(atLogicalPosition: 25)?.a.confidence == 30)
}

@Test("MSF supported handoff replay is repeatable and does not consume or mutate acquisition state")
func acquisitionReplayRepeatability() throws {
  var acquisition = try acquisitionCandidate(unknown: acquisitionMask(17))
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + acquisitionMinute, aBits: 0x132_706a_347e, bBits: 0x1a,
        unknown: acquisitionMask(17))) == .updated)
  let before = acquisition
  let first = try #require(acquisition.supportedAcquisition())
  let second = try #require(acquisition.supportedAcquisition())
  expectAcquisitionState(acquisition, matches: before)
  #expect(first.anchorCalendarDateTime == second.anchorCalendarDateTime)
  #expect(first.currentCalendarDateTime == second.currentCalendarDateTime)
  #expect(
    first.anchorMarkerTime == second.anchorMarkerTime
      && first.lastMarkerTime == second.lastMarkerTime)
  #expect(first.minuteIndex == second.minuteIndex && first.summerTime == second.summerTime)
  for position in 17...59 {
    #expect(
      first.evidence.second(atLogicalPosition: position)
        == second.evidence.second(atLogicalPosition: position))
  }
  #expect(
    acquisition.receive(
      completedFrame: fixedAcquisitionFrame(
        at: acquisitionStart + 2 * acquisitionMinute, aBits: 0x132_706a_357e,
        unknown: acquisitionMask(17))) == .updated)
  #expect(
    acquisition.supportedAcquisition()?.evidence.second(atLogicalPosition: 58)?.b.confidence
      == 3)
}

@Test(
  "MSF informative-frame counter saturates independently of ambiguity and bounded history",
  arguments: [254, 255, 256, 300])
func acquisitionInformativeCounter(_ count: Int) throws {
  var acquisition = MSFClockAcquisition()
  let unknown =
    acquisitionMask(24) | acquisitionMask(54) | acquisitionMask(36...38) | acquisitionMask(56)
  for index in 0..<count {
    let total = 33 + index
    #expect(
      acquisition.receive(
        completedFrame: encodedAcquisitionFrame(
          acquisitionCalendar(hour: 14 + total / 60, minute: total % 60),
          at: acquisitionStart + UInt64(index) * acquisitionMinute, unknown: unknown))
        == .updated)
  }
  #expect(acquisition.informativeFrameCount == min(count, 255))
  #expect(acquisition.status == .ambiguous && acquisition.hypothesisCount == 2)
  #expect(acquisition.supportedAcquisition() == nil)
  let total = 33 + count
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        acquisitionCalendar(hour: 14 + total / 60, minute: total % 60),
        at: acquisitionStart + UInt64(count) * acquisitionMinute)) == .updated)
  #expect(acquisition.status == .supported && acquisition.informativeFrameCount == 255)
}

@Test(
  "MSF acquisition separates unknown Summer Time from actual GMT and BST evidence",
  arguments: [Optional<Bool>.none, false, true])
func acquisitionSummerTimeEvidence(_ summerTime: Bool?) throws {
  let unknown = acquisitionMask(17) | (summerTime == nil ? acquisitionMask(58) : 0)
  let first = acquisitionCalendar(summerTime: summerTime ?? false)
  let next = acquisitionCalendar(minute: 34, summerTime: summerTime ?? false)
  var acquisition = try acquisitionCandidate(first, unknown: unknown)
  // Calendar hypotheses deliberately exclude Summer Time from enumeration.
  #expect(acquisition.currentHypothesis == first.settingTimeZone(nil))
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        next,
        at: acquisitionStart + acquisitionMinute, unknown: unknown)) == .updated)
  #expect(acquisition.hypothesisCount == 1)
  #expect(acquisition.currentHypothesis == next.settingTimeZone(nil))
  let handoff = try #require(acquisition.supportedAcquisition())
  #expect(handoff.summerTime == summerTime)
  #expect(handoff.anchorCalendarDateTime == first.settingTimeZone(summerTime.map { $0 ? .bst : .gmt }))
  #expect(handoff.currentCalendarDateTime == next.settingTimeZone(summerTime.map { $0 ? .bst : .gmt }))
  #expect(handoff.evidence.second(atLogicalPosition: 58)?.b.value == summerTime)
  #expect(
    handoff.evidence.second(atLogicalPosition: 58)?.b.confidence == (summerTime == nil ? 0 : 2))
  #expect(handoff.evidence.second(atLogicalPosition: 17)?.a.confidence == 0)
  #expect(handoff.evidence.second(atLogicalPosition: 18)?.a.confidence == 2)
  #expect(handoff.evidence.second(atLogicalPosition: 25)?.a.confidence == 30)
}

@Test(
  "MSF opposite B58 observations preserve prior status without rejecting calendar candidates",
  arguments: [false, true])
func acquisitionContradictorySummerTime(_ initial: Bool) throws {
  var acquisition = try acquisitionCandidate(
    acquisitionCalendar(summerTime: initial),
    unknown: acquisitionMask(17))
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        acquisitionCalendar(minute: 34, summerTime: !initial),
        at: acquisitionStart + acquisitionMinute, unknown: acquisitionMask(17))) == .updated
  )
  let handoff = try #require(acquisition.supportedAcquisition())
  #expect(acquisition.hypothesisCount == 1 && acquisition.informativeFrameCount == 2)
  #expect(handoff.summerTime == initial)
  #expect(handoff.currentCalendarDateTime == acquisitionCalendar(minute: 34, summerTime: initial))
  #expect(handoff.evidence.second(atLogicalPosition: 58)?.b.confidence == 1)
}

@Test(
  "MSF missing B58 ages status to unknown and later trustworthy reception can reseed it",
  arguments: [false, true])
func acquisitionMissingSummerTime(_ initial: Bool) throws {
  var acquisition = try acquisitionCandidate(
    acquisitionCalendar(summerTime: initial),
    unknown: acquisitionMask(17))
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        acquisitionCalendar(minute: 34, summerTime: initial),
        at: acquisitionStart + acquisitionMinute,
        unknown: acquisitionMask(17) | acquisitionMask(58))) == .updated)
  let missing = try #require(acquisition.supportedAcquisition())
  #expect(missing.summerTime == nil)
  #expect(missing.currentCalendarDateTime == acquisitionCalendar(minute: 34, summerTime: nil))
  #expect(missing.evidence.second(atLogicalPosition: 58)?.b.confidence == 0)
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        acquisitionCalendar(minute: 35, summerTime: !initial),
        at: acquisitionStart + 2 * acquisitionMinute, unknown: acquisitionMask(17)))
      == .updated)
  let reseeded = try #require(acquisition.supportedAcquisition())
  #expect(reseeded.summerTime == !initial)
  #expect(reseeded.evidence.second(atLogicalPosition: 58)?.b.confidence == 1)
}

@Test(
  "MSF a civil-time jump in partial evidence resets rather than authoritatively resynchronising",
  arguments: [
    (
      acquisitionCalendar(hour: 0, minute: 59, summerTime: false),
      acquisitionCalendar(hour: 2, minute: 0, summerTime: true)
    ),
    (
      acquisitionCalendar(hour: 1, minute: 59, summerTime: true),
      acquisitionCalendar(hour: 1, minute: 0, summerTime: false)
    ),
  ])
func acquisitionPartialCivilTimeJump(
  _ first: CalendarDateTimeComponents, _ next: CalendarDateTimeComponents
)
  throws
{
  var acquisition = try acquisitionCandidate(first, unknown: acquisitionMask(17))
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        next,
        at: acquisitionStart + acquisitionMinute, unknown: acquisitionMask(17)))
      == .reset(.incompatibleEvidence))
  #expect(acquisition.supportedAcquisition() == nil)
  #expect(acquisition.status == .unacquired)
}

@Test(
  "MSF actual acquisition handoffs start the clock with incomplete confidence and a fixed anchor",
  arguments: [Optional<Bool>.none, false, true])
func acquisitionClockHandoffAndProgression(_ summerTime: Bool?) throws {
  let unknown = acquisitionMask(17) | (summerTime == nil ? acquisitionMask(58) : 0)
  var acquisition = try acquisitionCandidate(
    acquisitionCalendar(summerTime: summerTime ?? false), unknown: unknown)
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        acquisitionCalendar(minute: 34, summerTime: summerTime ?? false),
        at: acquisitionStart + acquisitionMinute + 200_000, unknown: unknown)) == .updated)
  let handoff = try #require(acquisition.supportedAcquisition())
  var clock = MSFClockModel()
  #expect(clock.start(from: handoff) == .acquiredFromPartial(handoff.currentCalendarDateTime))
  #expect(clock.isAcquired && clock.anchorMarkerTime == acquisitionStart)
  let received = try #require(clock.currentSnapshot(at: handoff.lastMarkerTime))
  #expect(
    received.calendarDateTime
      == acquisitionCalendar(minute: 34, summerTime: summerTime))
  #expect(received.clockState.year == .unknown)
  #expect(received.clockState.month == .confirmed)
  #expect(received.clockState.timeZone == (summerTime == nil ? .unknown : .candidate))
  let later = try #require(
    clock.currentSnapshot(at: acquisitionStart + 3 * acquisitionMinute + 1_000_000))
  #expect(
    later.calendarDateTime
      == acquisitionCalendar(minute: 36, second: 1, summerTime: summerTime))
  #expect(clock.currentCalendarDateTime == handoff.currentCalendarDateTime)
  #expect(clock.anchorMarkerTime == acquisitionStart)
  #expect(clock.evidence.second(atLogicalPosition: 25)?.a.confidence == 30)
}

@Test(
  "MSF later complete frames corroborate or resynchronise real acquisition handoffs",
  arguments: [
    (Optional<Bool>.none, false, false), (nil, true, false),
    (false, false, false), (true, true, false), (false, true, false), (true, false, false),
    (nil, true, true), (true, true, true),
  ])
func acquisitionClockAuthoritativeFrame(
  _ initialSummerTime: Bool?, _ receivedSummerTime: Bool,
  _ differentMinute: Bool
) throws {
  let unknown = acquisitionMask(17) | (initialSummerTime == nil ? acquisitionMask(58) : 0)
  var acquisition = try acquisitionCandidate(
    acquisitionCalendar(summerTime: initialSummerTime ?? false), unknown: unknown)
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        acquisitionCalendar(minute: 34, summerTime: initialSummerTime ?? false),
        at: acquisitionStart + acquisitionMinute, unknown: unknown)) == .updated)
  let handoff = try #require(acquisition.supportedAcquisition())
  var clock = MSFClockModel()
  #expect(clock.start(from: handoff) == .acquiredFromPartial(handoff.currentCalendarDateTime))
  let expected = acquisitionCalendar(minute: 35, summerTime: initialSummerTime)
  let actual = acquisitionCalendar(
    minute: differentMinute ? 43 : 35, summerTime: receivedSummerTime)
  let event = clock.receive(
    completedFrame: encodedAcquisitionFrame(
      actual,
      at: acquisitionStart + 2 * acquisitionMinute, unknown: 0))
  let resynchronises =
    differentMinute || (initialSummerTime != nil && initialSummerTime != receivedSummerTime)
  #expect(
    event
      == (resynchronises
        ? .resynchronised(expected: expected, received: actual) : .corroborated(actual)))
  #expect(clock.currentCalendarDateTime == actual)
  #expect(clock.anchorMarkerTime == acquisitionStart + 2 * acquisitionMinute)
  let snapshot = try #require(clock.currentSnapshot(at: acquisitionStart + 2 * acquisitionMinute))
  #expect(snapshot.clockState.year == .confirmed)
  #expect(snapshot.clockState.timeZone == .confirmed)
}

private func acquisitionCalendar(
  year: Int = 2026, month: Int = 9, day: Int = 30, weekday: Int = 3,
  hour: Int = 14, minute: Int = 33, second: Int = 0, summerTime: Bool? = true
) -> CalendarDateTimeComponents {
  CalendarDateTimeComponents(
    year: year, month: month, dayOfMonth: day, dayOfWeek: weekday,
    hour: hour, minute: minute, second: second, timeZone: summerTime.map { $0 ? .bst : .gmt })
}

private func acquisitionMask(_ position: Int) -> UInt64 { UInt64(1) << (59 - position) }

private func acquisitionMask(_ positions: ClosedRange<Int>) -> UInt64 {
  positions.reduce(0) { $0 | acquisitionMask($1) }
}

private func fixedAcquisitionFrame(
  at timestamp: UInt64 = acquisitionStart, aBits: UInt64 = 0x132_706a_337e,
  bBits: UInt64 = 0x1e, unknown: UInt64 = UInt64(1) << 1,
  aFlip: UInt64 = 0, bFlip: UInt64 = 0,
  dataCount: Int = 59, hasOpeningMarker: Bool = true
) -> MSFCompletedFrame {
  MSFCompletedFrame(
    aBits: aBits ^ aFlip, bBits: bBits ^ bFlip,
    unknownBits: unknown, dataCount: dataCount, hasOpeningMarker: hasOpeningMarker,
    closingMarkerTime: timestamp)
}

private func encodedAcquisitionFrame(
  _ calendar: CalendarDateTimeComponents, at timestamp: UInt64,
  unknown: UInt64 = UInt64(1) << 1
) -> MSFCompletedFrame {
  // The independently tested production encoder supplies varied reception
  // inputs. Expected dates, candidate sets and replay confidence are explicit.
  let expected = MSFExpectedFrame(calendarDateTime: calendar)
  var a: UInt64 = 0
  var b: UInt64 = 0
  for position in 17...59 {
    let mask = acquisitionMask(position)
    if expected.bit(at: position, channel: .a) == true { a |= mask }
    if expected.bit(at: position, channel: .b) == true { b |= mask }
  }
  return fixedAcquisitionFrame(at: timestamp, aBits: a, bBits: b, unknown: unknown)
}

private func acquisitionCandidate(
  _ calendar: CalendarDateTimeComponents = acquisitionCalendar(),
  unknown: UInt64 = UInt64(1) << 1
) throws -> MSFClockAcquisition {
  var acquisition = MSFClockAcquisition()
  #expect(
    acquisition.receive(
      completedFrame: encodedAcquisitionFrame(
        calendar,
        at: acquisitionStart, unknown: unknown)) == .updated)
  #expect(acquisition.status == .candidate && acquisition.hypothesisCount == 1)
  #expect(acquisition.informativeFrameCount == 1)
  return acquisition
}

private func expectAcquisitionState(
  _ actual: MSFClockAcquisition, matches expected: MSFClockAcquisition
) {
  #expect(actual.status == expected.status)
  #expect(actual.hypothesisCount == expected.hypothesisCount)
  #expect(actual.informativeFrameCount == expected.informativeFrameCount)
  #expect(actual.exceedsCapacity == expected.exceedsCapacity)
  #expect(actual.anchorMarkerTime == expected.anchorMarkerTime)
  #expect(actual.currentMinuteIndex == expected.currentMinuteIndex)
  for index in 0..<expected.hypothesisCount {
    #expect(actual.hypothesis(at: index) == expected.hypothesis(at: index))
  }
}

@Test("Acquisition exposes only hour/minute consensus without requiring a unique calendar", arguments: [false, true])
func acquisitionDisplayConsensus(_ minuteUnknown: Bool) throws {
  var acquisition = MSFClockAcquisition()
  let unknown =
    acquisitionMask(minuteUnknown ? MSFField.minute.positions : MSFField.hour.positions) | acquisitionMask(57)
  #expect(acquisition.receive(completedFrame: fixedAcquisitionFrame(unknown: unknown)) == .updated)
  #expect(acquisition.status == .ambiguous)
  let snapshot = try #require(acquisition.currentSnapshot(at: acquisitionStart + 30_123_456))
  #expect(snapshot.clockState.hour == (minuteUnknown ? .candidate : .unknown))
  #expect(snapshot.clockState.minute == (minuteUnknown ? .unknown : .candidate))
  if minuteUnknown {
    #expect(snapshot.calendarDateTime.hour == 14)
  } else {
    #expect(snapshot.calendarDateTime.minute == 33)
  }
  #expect(snapshot.calendarDateTime.year == nil && snapshot.calendarDateTime.month == nil)
  #expect(snapshot.calendarDateTime.dayOfMonth == nil && snapshot.calendarDateTime.dayOfWeek == nil)
  #expect(snapshot.calendarDateTime.timeZone == nil)
  #expect(snapshot.calendarDateTime.hour == (minuteUnknown ? 14 : nil))
  #expect(snapshot.calendarDateTime.minute == (minuteUnknown ? nil : 33))
  #expect(!snapshot.hasAcquiredTime)
  #expect(snapshot.hasHour == minuteUnknown && snapshot.hasMinute == !minuteUnknown)
  #expect(snapshot.hasSecondTiming)
  #expect(snapshot.calendarDateTime.second == 30 && snapshot.subsecondMicroseconds == 123_456)
  #expect(snapshot.clockState.year == .unknown && snapshot.clockState.timeZone == .unknown)
  #expect(acquisition.status == .ambiguous && acquisition.supportedAcquisition() == nil)
  #expect(acquisition.currentSnapshot(at: acquisitionStart - 1) == nil)
}

@Test("Projected ambiguous minutes cannot manufacture a known hour across an uncertain carry")
func acquisitionDisplayCarry() throws {
  var acquisition = MSFClockAcquisition()
  let unknown = acquisitionMask(MSFField.minute.positions) | acquisitionMask(57)
  #expect(acquisition.receive(completedFrame: fixedAcquisitionFrame(unknown: unknown)) == .updated)
  let before = try #require(acquisition.currentSnapshot(at: acquisitionStart + 59_999_999))
  #expect(before.clockState.hour == .candidate && before.calendarDateTime.hour == 14)
  let after = try #require(acquisition.currentSnapshot(at: acquisitionStart + acquisitionMinute))
  #expect(after.clockState.hour == .unknown && after.clockState.minute == .unknown)
  #expect(!before.hasAcquiredTime && before.hasHour && !before.hasMinute)
  #expect(!after.hasAcquiredTime && !after.hasHour && !after.hasMinute)
  #expect(after.hasSecondTiming && after.calendarDateTime.second == 0)
  let hourLater = try #require(acquisition.currentSnapshot(at: acquisitionStart + 60 * acquisitionMinute))
  #expect(hourLater.clockState.hour == .candidate && hourLater.calendarDateTime.hour == 15)
  #expect(MSFClockAcquisition().currentSnapshot(at: acquisitionStart) == nil)
}
