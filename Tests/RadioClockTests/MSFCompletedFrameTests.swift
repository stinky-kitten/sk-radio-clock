//
//  MSFCompletedFrameTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-13.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

@Test("MSF completed frame decodes a valid date and time")
func completedFrameValidDecode() {
  // Fixed 29 September fixture from old_tests/test_msf_clock.swift:
  // 2026-09-29 (Tuesday), 17:42.
  let frame = MSFCompletedFrame(
    aBits: 0x132_694b_c27e,
    bBits: 0x6,
    dataCount: 59,
    hasOpeningMarker: true
  )

  let result = frame.decode()

  #expect(result.decodeStatus == .valid)
  #expect(result.calendarDateTime?.year == 2026)
  #expect(result.calendarDateTime?.month == 9)
  #expect(result.calendarDateTime?.dayOfMonth == 29)
  #expect(result.calendarDateTime?.dayOfWeek == 2)
  #expect(result.calendarDateTime?.hour == 17)
  #expect(result.calendarDateTime?.minute == 42)
}

@Test("MSF completed frame rejects an unknown bit")
func completedFrameUnknownBitDecode() {
  let frame = MSFCompletedFrame(
    aBits: 0x132_694b_c27e,
    bBits: 0x6,
    unknownBits: 1,
    dataCount: 59,
    hasOpeningMarker: true
  )

  let result = frame.decode()

  #expect(result.decodeStatus == .missingData)
  #expect(result.calendarDateTime == nil)
}

@Test("MSF completed frame rejects an invalid frame length")
func completedFrameInvalidLengthDecode() {
  let frame = MSFCompletedFrame(
    aBits: 0x132_694b_c27e,
    bBits: 0x6,
    dataCount: 57,
    hasOpeningMarker: true
  )

  let result = frame.decode()

  #expect(result.decodeStatus == .invalidFrameLength)
  #expect(result.calendarDateTime == nil)
}

@Test("MSF completed frame needs all 43 suffix positions", arguments: [0, 1, 41, 42])
func completedFrameInsufficientData(_ count: Int) {
  expectRejection(knownGoodFrame(dataCount: count), status: .insufficientData)
}

@Test("MSF completed frame accepts normal and leap-minute lengths", arguments: [58, 59, 60])
func completedFrameAcceptedLength(_ count: Int) {
  expectFixtureCalendar(knownGoodFrame(dataCount: count))
}

@Test("MSF completed frame checks length with an opening marker", arguments: [43, 44, 56, 61, 64, 65])
func completedFrameOtherInvalidLengths(_ count: Int) {
  expectRejection(knownGoodFrame(dataCount: count), status: .invalidFrameLength)
}

@Test(
  "MSF completed frame accepts a sufficient suffix without an opening marker",
  arguments: [43, 44, 57, 58, 59, 60, 61, 64, 65])
func completedFrameWithoutOpeningMarker(_ count: Int) {
  expectFixtureCalendar(knownGoodFrame(dataCount: count, hasOpeningMarker: false))
}

@Test("MSF completed frame still needs 43 positions without an opening marker")
func completedFrameShortWithoutOpeningMarker() {
  expectRejection(
    knownGoodFrame(dataCount: 42, hasOpeningMarker: false), status: .insufficientData)
}

@Test("MSF completed frame rejects unknown positions throughout the suffix", arguments: [0, 21, 42])
func completedFrameUnknownSuffixPosition(_ offset: Int) {
  expectRejection(knownGoodFrame(unknownBits: UInt64(1) << offset), status: .missingData)
}

@Test("MSF completed frame ignores unknown positions outside the suffix", arguments: [43, 58])
func completedFrameUnknownPrefixPosition(_ offset: Int) {
  expectFixtureCalendar(knownGoodFrame(unknownBits: UInt64(1) << offset))
}

@Test("MSF completed frame ignores A/B prefix bits outside the calendar suffix")
func completedFramePrefixBits() {
  let prefix = UInt64(0xffff) << 43
  expectFixtureCalendar(
    knownGoodFrame(
      aBits: 0x132_694b_c27e | prefix, bBits: 0x6 | prefix))
}

@Test(
  "MSF completed frame ignores the closing timestamp when decoding",
  arguments: [UInt64(0), UInt64.max])
func completedFrameClosingTimestamp(_ timestamp: UInt64) {
  expectFixtureCalendar(knownGoodFrame(closingMarkerTime: timestamp))
}

@Test("MSF completed frame rejects changed fixed identifier bits", arguments: [0, 1, 7])
func completedFrameInvalidIdentifier(_ offset: Int) {
  expectRejection(
    knownGoodFrame(aBits: 0x132_694b_c27e ^ (UInt64(1) << offset)),
    status: .invalidIdentifier)
}

@Test("MSF completed frame rejects year parity failure")
func completedFrameYearParityFailure() {
  expectRejection(knownGoodFrame(bBits: 0x6 ^ (1 << 5)), status: .parityYear)
}

@Test("MSF completed frame rejects month/day parity failure")
func completedFrameMonthDayParityFailure() {
  expectRejection(knownGoodFrame(bBits: 0x6 ^ (1 << 4)), status: .parityMonthDay)
}

@Test("MSF completed frame rejects weekday parity failure")
func completedFrameWeekdayParityFailure() {
  expectRejection(knownGoodFrame(bBits: 0x6 ^ (1 << 3)), status: .parityDayOfWeek)
}

@Test("MSF completed frame rejects hour/minute parity failure")
func completedFrameHourMinuteParityFailure() {
  expectRejection(knownGoodFrame(bBits: 0x6 ^ (1 << 2)), status: .parityHourMinute)
}

@Test(
  "MSF completed frame rejects parity corruption in A-channel data",
  arguments: [
    (42, MSFDecodeStatus.parityYear),
    (34, MSFDecodeStatus.parityMonthDay),
    (23, MSFDecodeStatus.parityDayOfWeek),
    (20, MSFDecodeStatus.parityHourMinute),
  ])
func completedFrameADataParityFailure(_ offset: Int, _ status: MSFDecodeStatus) {
  expectRejection(
    knownGoodFrame(aBits: 0x132_694b_c27e ^ (UInt64(1) << offset)), status: status)
}

@Test("MSF completed frame rejects malformed year BCD", arguments: [UInt64(0x2a), 0xa6, 0xff])
func completedFrameInvalidYearBCD(_ bits: UInt64) {
  // Valid two-digit BCD cannot exceed 99; invalidYear requires a digit above 9.
  expectRejection(
    frameReplacingFieldBits(bits, shift: 35, width: 8, parityOffset: 5),
    status: .invalidYear)
}

@Test(
  "MSF completed frame rejects out-of-range or malformed months",
  arguments: [UInt64(0x00), 0x13, 0x19, 0x0a, 0x1a, 0x1f])
func completedFrameInvalidMonth(_ bits: UInt64) {
  expectRejection(
    frameReplacingFieldBits(bits, shift: 30, width: 5, parityOffset: 4),
    status: .invalidMonth)
}

@Test(
  "MSF completed frame rejects out-of-range or malformed days",
  arguments: [UInt64(0x00), 0x32, 0x39, 0x2a, 0x3f])
func completedFrameInvalidDay(_ bits: UInt64) {
  expectRejection(
    frameReplacingFieldBits(bits, shift: 24, width: 6, parityOffset: 4),
    status: .invalidDayOfMonth)
}

@Test("MSF completed frame rejects weekday seven")
func completedFrameInvalidWeekday() {
  expectRejection(
    frameReplacingFieldBits(7, shift: 21, width: 3, parityOffset: 3),
    status: .invalidDayOfWeek)
}

@Test(
  "MSF completed frame rejects out-of-range or malformed hours",
  arguments: [UInt64(0x24), 0x29, 0x30, 0x1a, 0x3f])
func completedFrameInvalidHour(_ bits: UInt64) {
  expectRejection(
    frameReplacingFieldBits(bits, shift: 15, width: 6, parityOffset: 2),
    status: .invalidHour)
}

@Test(
  "MSF completed frame rejects out-of-range or malformed minutes",
  arguments: [UInt64(0x60), 0x69, 0x70, 0x4a, 0x7f])
func completedFrameInvalidMinute(_ bits: UInt64) {
  expectRejection(
    frameReplacingFieldBits(bits, shift: 8, width: 7, parityOffset: 2),
    status: .invalidMinute)
}

// Fixed packed inputs established from the NPL field weights and odd parity,
// independently of the production encoder/decoder. Weekdays use 0=Sunday.
// https://www.npl.co.uk/products-services/time-frequency/msf-radio-time-signal/msf_time_date_code
@Test(
  "MSF completed frame decodes calendar boundaries and BCD transitions",
  arguments: [
    (UInt64(0x41c0_007e), UInt64(0x3c), 2000, 1, 1, 6, 0, 0),
    (UInt64(0x4cc_b191_d97e), UInt64(0x20), 2099, 12, 31, 4, 23, 59),
    (UInt64(0x4a_4964_897e), UInt64(0x3e), 2009, 9, 9, 3, 9, 9),
    (UInt64(0x84_1008_107e), UInt64(0x1e), 2010, 10, 10, 0, 10, 10),
    (UInt64(0x120_a991_d97e), UInt64(0x30), 2024, 2, 29, 4, 23, 59),
    (UInt64(0x140_a951_d97e), UInt64(0x30), 2028, 2, 29, 2, 23, 59),
    (UInt64(0x132_7071_d97e), UInt64(0x1a), 2026, 9, 30, 3, 23, 59),
    (UInt64(0x134_0180_007e), UInt64(0x16), 2026, 10, 1, 4, 0, 0),
    (UInt64(0x130_71d1_d97e), UInt64(0x18), 2026, 1, 31, 6, 23, 59),
    (UInt64(0x134_b191_d97e), UInt64(0x00), 2026, 12, 31, 4, 23, 59),
    (UInt64(0x138_41a0_007e), UInt64(0x3c), 2027, 1, 1, 5, 0, 0),
    (UInt64(0x131_3089_347e), UInt64(0x02), 2026, 4, 30, 4, 12, 34),
    (UInt64(0x131_41a9_357e), UInt64(0x0e), 2026, 5, 1, 5, 12, 35),
  ])
func completedFrameCalendarBoundaries(
  _ aBits: UInt64, _ bBits: UInt64, _ year: Int, _ month: Int,
  _ day: Int, _ weekday: Int, _ hour: Int, _ minute: Int
) {
  expectCalendar(
    knownGoodFrame(aBits: aBits, bBits: bBits), year: year, month: month,
    day: day, weekday: weekday, hour: hour, minute: minute)
}

@Test(
  "Parity-valid MSF frames with inconsistent dates cannot acquire or re-anchor the clock",
  arguments: [
    // September has no day 31; 2026 is not a leap year; September 29 is Tuesday.
    (UInt64(0x132_714b_c27e), UInt64(0x06), MSFDecodeStatus.invalidDayOfMonth),
    (UInt64(0x130_a90b_c27e), UInt64(0x1c), MSFDecodeStatus.invalidDayOfMonth),
    (UInt64(0x132_690b_c27e), UInt64(0x0e), MSFDecodeStatus.invalidDayOfWeek),
  ])
func completedFrameRejectsInconsistentCalendar(_ aBits: UInt64, _ bBits: UInt64, _ status: MSFDecodeStatus) throws {
  let marker = MSFMinuteGrid.durationUs
  let invalid = knownGoodFrame(aBits: aBits, bBits: bBits, closingMarkerTime: marker)
  expectRejection(invalid, status: status)

  var unacquired = MSFClockModel()
  #expect(unacquired.receive(completedFrame: invalid) == .unacquired)
  #expect(!unacquired.isAcquired)
  #expect(unacquired.anchorMarkerTime == nil)

  var clock = MSFClockModel()
  let initial = knownGoodFrame()
  let decoded = try #require(initial.decode().calendarDateTime)
  let acquired = decoded.settingTimeZone(.bst)
  #expect(clock.receive(completedFrame: initial) == .acquired(acquired))
  let predicted = try #require(clock.currentSnapshot(at: marker)).calendarDateTime

  let event = clock.receive(completedFrame: invalid)
  guard case .updated(let estimate, _, let contradictions, _) = event else {
    Issue.record("Expected an evidence update without re-anchoring, got \(event)")
    return
  }
  #expect(contradictions > 0)
  #expect(estimate == predicted)
  #expect(clock.anchorMarkerTime == initial.closingMarkerTime)
  #expect(clock.currentCalendarDateTime == predicted)
}

@Test("MSF completed frame decodes summer-time frames with a neutral calendar flag")
func completedFrameDecodedSummerTimeFlag() {
  let summerFrame = knownGoodFrame()
  #expect(summerFrame.summerTime == true)
  expectFixtureCalendar(summerFrame)
  let winterFrame = knownGoodFrame(bBits: 0x6 ^ (1 << 1))
  #expect(winterFrame.summerTime == false)
  expectFixtureCalendar(winterFrame)
}

@Test("MSF completed frame checks available data before length and content")
func completedFrameInsufficientDataPrecedence() {
  expectRejection(
    knownGoodFrame(aBits: 0, bBits: 0, unknownBits: 1, dataCount: 42),
    status: .insufficientData)
}

@Test("MSF completed frame checks length before unknown data and identifier")
func completedFrameLengthPrecedence() {
  expectRejection(
    knownGoodFrame(aBits: 0, bBits: 0, unknownBits: 1, dataCount: 57),
    status: .invalidFrameLength)
}

@Test("MSF completed frame checks unknown data before identifier and parity")
func completedFrameUnknownDataPrecedence() {
  expectRejection(
    knownGoodFrame(aBits: 0x132_694b_c27e ^ 1, bBits: 0x6 ^ (1 << 5), unknownBits: 1 << 21),
    status: .missingData)
}

@Test("MSF completed frame checks identifier before every parity group")
func completedFrameIdentifierPrecedence() {
  expectRejection(
    knownGoodFrame(aBits: 0x132_694b_c27e ^ 1, bBits: 0x6 ^ 0x3c),
    status: .invalidIdentifier)
}

@Test("MSF completed frame checks year parity before later parity groups")
func completedFrameYearParityPrecedence() {
  expectRejection(knownGoodFrame(bBits: 0x6 ^ 0x3c), status: .parityYear)
}

@Test("MSF completed frame checks month/day parity before weekday and time parity")
func completedFrameMonthDayParityPrecedence() {
  expectRejection(knownGoodFrame(bBits: 0x6 ^ 0x1c), status: .parityMonthDay)
}

@Test("MSF completed frame checks weekday parity before time parity")
func completedFrameWeekdayParityPrecedence() {
  expectRejection(knownGoodFrame(bBits: 0x6 ^ 0x0c), status: .parityDayOfWeek)
}

@Test("MSF completed frame checks all parity before calendar values")
func completedFrameParityBeforeCalendar() {
  let invalidMonth = frameReplacingFieldBits(0, shift: 30, width: 5, parityOffset: 4)
  expectRejection(
    knownGoodFrame(aBits: invalidMonth.aBits, bBits: invalidMonth.bBits ^ (1 << 2)),
    status: .parityHourMinute)
}

@Test("MSF completed frame checks year BCD before month")
func completedFrameYearBeforeMonth() {
  let invalidMonth = frameReplacingFieldBits(0, shift: 30, width: 5, parityOffset: 4)
  expectRejection(
    frameReplacingFieldBits(0xa6, shift: 35, width: 8, parityOffset: 5, in: invalidMonth),
    status: .invalidYear)
}

@Test("MSF completed frame checks month before day")
func completedFrameMonthBeforeDay() {
  let invalidDay = frameReplacingFieldBits(0, shift: 24, width: 6, parityOffset: 4)
  expectRejection(
    frameReplacingFieldBits(0, shift: 30, width: 5, parityOffset: 4, in: invalidDay),
    status: .invalidMonth)
}

@Test("MSF completed frame checks day before weekday")
func completedFrameDayBeforeWeekday() {
  let invalidWeekday = frameReplacingFieldBits(7, shift: 21, width: 3, parityOffset: 3)
  expectRejection(
    frameReplacingFieldBits(0, shift: 24, width: 6, parityOffset: 4, in: invalidWeekday),
    status: .invalidDayOfMonth)
}

@Test("MSF completed frame checks weekday before hour")
func completedFrameWeekdayBeforeHour() {
  let invalidHour = frameReplacingFieldBits(0x24, shift: 15, width: 6, parityOffset: 2)
  expectRejection(
    frameReplacingFieldBits(7, shift: 21, width: 3, parityOffset: 3, in: invalidHour),
    status: .invalidDayOfWeek)
}

@Test("MSF completed frame checks hour before minute")
func completedFrameHourBeforeMinute() {
  let invalidMinute = frameReplacingFieldBits(0x60, shift: 8, width: 7, parityOffset: 2)
  expectRejection(
    frameReplacingFieldBits(0x24, shift: 15, width: 6, parityOffset: 2, in: invalidMinute),
    status: .invalidHour)
}

@Test("Markerless MSF completed frame rejects invalid identifiers", arguments: [0, 1, 7])
func markerlessCompletedFrameInvalidIdentifier(_ offset: Int) {
  expectRejection(
    knownGoodFrame(
      aBits: 0x132_694b_c27e ^ (UInt64(1) << offset),
      dataCount: 43, hasOpeningMarker: false),
    status: .invalidIdentifier)
}

@Test(
  "Markerless MSF completed frame rejects A-data parity failures",
  arguments: [
    (42, MSFDecodeStatus.parityYear),
    (34, MSFDecodeStatus.parityMonthDay),
    (23, MSFDecodeStatus.parityDayOfWeek),
    (20, MSFDecodeStatus.parityHourMinute),
  ])
func markerlessCompletedFrameAParity(_ offset: Int, _ status: MSFDecodeStatus) {
  expectRejection(
    knownGoodFrame(
      aBits: 0x132_694b_c27e ^ (UInt64(1) << offset),
      dataCount: 43, hasOpeningMarker: false),
    status: status)
}

@Test(
  "Markerless MSF completed frame rejects B-parity failures",
  arguments: [
    (5, MSFDecodeStatus.parityYear),
    (4, MSFDecodeStatus.parityMonthDay),
    (3, MSFDecodeStatus.parityDayOfWeek),
    (2, MSFDecodeStatus.parityHourMinute),
  ])
func markerlessCompletedFrameBParity(_ offset: Int, _ status: MSFDecodeStatus) {
  expectRejection(
    knownGoodFrame(
      bBits: 0x6 ^ (UInt64(1) << offset), dataCount: 43, hasOpeningMarker: false),
    status: status)
}

// Fixed corruptions from the archived decoder tests, with odd parity retained:
// year A6 (invalid BCD), month 19, day 39, hour 37, minute 62, weekday 7.
@Test(
  "Markerless MSF completed frame rejects invalid calendar fields",
  arguments: [
    (UInt64(0x532_694b_c27e), UInt64(0x26), MSFDecodeStatus.invalidYear),
    (UInt64(0x136_694b_c27e), UInt64(0x16), MSFDecodeStatus.invalidMonth),
    (UInt64(0x132_794b_c27e), UInt64(0x16), MSFDecodeStatus.invalidDayOfMonth),
    (UInt64(0x132_695b_c27e), UInt64(0x02), MSFDecodeStatus.invalidHour),
    (UInt64(0x132_694b_e27e), UInt64(0x02), MSFDecodeStatus.invalidMinute),
    (UInt64(0x132_69eb_c27e), UInt64(0x06), MSFDecodeStatus.invalidDayOfWeek),
  ])
func markerlessCompletedFrameInvalidCalendar(
  _ aBits: UInt64, _ bBits: UInt64, _ status: MSFDecodeStatus
) {
  expectRejection(
    knownGoodFrame(aBits: aBits, bBits: bBits, dataCount: 43, hasOpeningMarker: false),
    status: status)
}

@Test("Markerless MSF completed frame rejects required unknown positions", arguments: [0, 21, 29, 42])
func markerlessCompletedFrameUnknownPosition(_ offset: Int) {
  expectRejection(
    knownGoodFrame(
      unknownBits: UInt64(1) << offset, dataCount: 43, hasOpeningMarker: false),
    status: .missingData)
}

private func knownGoodFrame(
  aBits: UInt64 = 0x132_694b_c27e, bBits: UInt64 = 0x6,
  unknownBits: UInt64 = 0, dataCount: Int = 59, hasOpeningMarker: Bool = true,
  closingMarkerTime: UInt64 = 0
) -> MSFCompletedFrame {
  MSFCompletedFrame(
    aBits: aBits, bBits: bBits, unknownBits: unknownBits, dataCount: dataCount,
    hasOpeningMarker: hasOpeningMarker, closingMarkerTime: closingMarkerTime)
}

private func frameReplacingFieldBits(
  _ bits: UInt64, shift: Int, width: Int, parityOffset: Int,
  in frame: MSFCompletedFrame = knownGoodFrame()
) -> MSFCompletedFrame {
  let mask = ((UInt64(1) << width) - 1) << shift
  let aBits = (frame.aBits & ~mask) | ((bits << shift) & mask)
  // Each changed A bit reverses its group's parity. Toggle the B parity bit
  // only for an odd number of changes, preserving the fixture's odd parity.
  let parityChange: UInt64 =
    (frame.aBits ^ aBits).nonzeroBitCount % 2 == 1
    ? UInt64(1) << parityOffset : 0
  return knownGoodFrame(aBits: aBits, bBits: frame.bBits ^ parityChange)
}

private func expectRejection(_ frame: MSFCompletedFrame, status: MSFDecodeStatus) {
  let result = frame.decode()
  #expect(result.decodeStatus == status)
  #expect(result.calendarDateTime == nil)
}

private func expectFixtureCalendar(_ frame: MSFCompletedFrame) {
  expectCalendar(frame, year: 2026, month: 9, day: 29, weekday: 2, hour: 17, minute: 42)
}

private func expectCalendar(
  _ frame: MSFCompletedFrame, year: Int, month: Int, day: Int,
  weekday: Int, hour: Int, minute: Int
) {
  let result = frame.decode()
  #expect(result.decodeStatus == .valid)
  #expect(result.calendarDateTime?.year == year)
  #expect(result.calendarDateTime?.month == month)
  #expect(result.calendarDateTime?.dayOfMonth == day)
  #expect(result.calendarDateTime?.dayOfWeek == weekday)
  #expect(result.calendarDateTime?.hour == hour)
  #expect(result.calendarDateTime?.minute == minute)
  #expect(result.calendarDateTime?.second == 0)
  #expect(result.calendarDateTime?.timeZone == nil)
}
