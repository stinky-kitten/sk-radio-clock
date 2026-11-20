//
//  MSFExpectedFrameTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-13.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

// Reference patterns use NPL's published bit weights, identifier and odd parity,
// independently of the production encoder, decoder and field-position helpers.
// Packed bit zero corresponds to logical position 59.
// https://www.npl.co.uk/products-services/time-frequency/msf-radio-time-signal/msf_time_date_code
@Test(
  "MSF expected frame encodes every calendar and structural bit",
  arguments: [
    (2026, 9, 29, 2, 17, 42, true, UInt64(0x132_694b_c27e), UInt64(0x06)),
    (2026, 9, 30, 3, 13, 26, true, UInt64(0x132_7069_a67e), UInt64(0x1e)),
    (2000, 1, 1, 6, 0, 0, false, UInt64(0x41c0_007e), UInt64(0x3c)),
    (2099, 12, 31, 4, 23, 59, false, UInt64(0x4cc_b191_d97e), UInt64(0x20)),
    (2009, 9, 9, 3, 9, 9, true, UInt64(0x4a_4964_897e), UInt64(0x3e)),
    (2010, 10, 10, 0, 10, 10, true, UInt64(0x84_1008_107e), UInt64(0x1e)),
    (2019, 1, 19, 6, 19, 19, false, UInt64(0xc8_59cc_997e), UInt64(0x1c)),
    (2020, 1, 20, 1, 20, 20, false, UInt64(0x100_6030_207e), UInt64(0x14)),
    (2026, 9, 29, 2, 17, 59, true, UInt64(0x132_694b_d97e), UInt64(0x06)),
    (2026, 9, 29, 2, 18, 0, true, UInt64(0x132_694c_007e), UInt64(0x06)),
    (2024, 2, 29, 4, 23, 59, false, UInt64(0x120_a991_d97e), UInt64(0x30)),
    (2024, 3, 1, 5, 0, 0, false, UInt64(0x120_c1a0_007e), UInt64(0x2c)),
    (2040, 1, 1, 0, 0, 0, false, UInt64(0x200_4100_007e), UInt64(0x1c)),
    (2026, 4, 4, 6, 4, 4, true, UInt64(0x131_04c2_047e), UInt64(0x1e)),
    (2026, 2, 2, 1, 2, 2, false, UInt64(0x130_8221_027e), UInt64(0x14)),
  ])
func expectedFrameReferenceEncoding(
  _ year: Int, _ month: Int, _ day: Int, _ weekday: Int,
  _ hour: Int, _ minute: Int, _ summerTime: Bool,
  _ aBits: UInt64, _ bBits: UInt64
) {
  let expected = MSFExpectedFrame(
    calendarDateTime: expectedCalendar(
      year: year, month: month, day: day, weekday: weekday,
      hour: hour, minute: minute, summerTime: summerTime))
  for position in 17...59 {
    let mask = UInt64(1) << (59 - position)
    #expect(expected.bit(at: position, channel: .a) == (aBits & mask != 0))
    if (54...58).contains(position) {
      #expect(expected.bit(at: position, channel: .b) == (bBits & mask != 0))
    } else {
      #expect(expected.bit(at: position, channel: .b) == nil)
    }
  }
}

@Test(
  "MSF expected year helper uses two-digit BCD in A17 through A24",
  arguments: [
    (UInt8(0), UInt64(0)), (1, 0x8_0000_0000), (9, 0x48_0000_0000),
    (10, 0x80_0000_0000), (19, 0xc8_0000_0000), (20, 0x100_0000_0000),
    (26, 0x130_0000_0000), (59, 0x2c8_0000_0000), (99, 0x4c8_0000_0000),
  ])
func expectedFrameYearBits(_ value: UInt8, _ expected: UInt64) {
  #expect(MSFExpectedFrame.bcdBits(forValue: value, inField: .year) == expected)
}

@Test(
  "MSF expected month helper maps A25 through A29",
  arguments: [
    (UInt8(1), UInt64(0x4000_0000)), (9, 0x2_4000_0000),
    (10, 0x4_0000_0000), (12, 0x4_8000_0000),
  ])
func expectedFrameMonthBits(_ value: UInt8, _ expected: UInt64) {
  #expect(MSFExpectedFrame.bcdBits(forValue: value, inField: .month) == expected)
}

@Test(
  "MSF expected day helper maps A30 through A35",
  arguments: [
    (UInt8(1), UInt64(0x1000000)), (9, 0x9000000), (10, 0x1000_0000),
    (19, 0x1900_0000), (20, 0x2000_0000), (29, 0x2900_0000), (31, 0x3100_0000),
  ])
func expectedFrameDayBits(_ value: UInt8, _ expected: UInt64) {
  #expect(MSFExpectedFrame.bcdBits(forValue: value, inField: .dayOfMonth) == expected)
}

@Test(
  "MSF expected weekday helper maps Sunday through Saturday to A36 through A38",
  arguments: [
    (UInt8(0), UInt64(0)), (1, 0x200000), (2, 0x400000), (3, 0x600000),
    (4, 0x800000), (5, 0xa00000), (6, 0xc00000),
  ])
func expectedFrameWeekdayBits(_ value: UInt8, _ expected: UInt64) {
  #expect(MSFExpectedFrame.bcdBits(forValue: value, inField: .dayOfWeek) == expected)
}

@Test(
  "MSF expected hour helper maps A39 through A44",
  arguments: [
    (UInt8(0), UInt64(0)), (9, 0x48000), (10, 0x80000),
    (19, 0xc8000), (20, 0x100000), (23, 0x118000),
  ])
func expectedFrameHourBits(_ value: UInt8, _ expected: UInt64) {
  #expect(MSFExpectedFrame.bcdBits(forValue: value, inField: .hour) == expected)
}

@Test(
  "MSF expected minute helper maps A45 through A51",
  arguments: [
    (UInt8(0), UInt64(0)), (9, 0x900), (10, 0x1000),
    (19, 0x1900), (20, 0x2000), (42, 0x4200), (59, 0x5900),
  ])
func expectedFrameMinuteBits(_ value: UInt8, _ expected: UInt64) {
  #expect(MSFExpectedFrame.bcdBits(forValue: value, inField: .minute) == expected)
}

@Test(
  "MSF expected identifier is always A52 through A59 equal to 01111110",
  arguments: [false, true], [false, true])
func expectedFrameIdentifier(_ summerTime: Bool, _ predictSummerTime: Bool) {
  let expected = MSFExpectedFrame(
    calendarDateTime: expectedCalendar(summerTime: summerTime),
    predictSummerTime: predictSummerTime)
  let identifier = Array("01111110".utf8)
  for index in 0..<8 {
    #expect(expected.bit(at: 52 + index, channel: .a) == (identifier[index] == 49))
  }
}

@Test(
  "MSF expected parity handles independently counted odd and even A populations",
  arguments: [
    (2026, 9, 29, 2, 17, 42, 3, 5, 1, 6),
    (2000, 1, 1, 6, 0, 0, 0, 2, 2, 0),
    (2099, 12, 31, 4, 23, 59, 4, 5, 1, 7),
  ])
func expectedFrameOddParityGroups(
  _ year: Int, _ month: Int, _ day: Int, _ weekday: Int, _ hour: Int, _ minute: Int,
  _ yearOnes: Int, _ monthDayOnes: Int, _ weekdayOnes: Int, _ timeOnes: Int
) {
  let expected = MSFExpectedFrame(
    calendarDateTime: expectedCalendar(
      year: year, month: month, day: day, weekday: weekday, hour: hour, minute: minute))
  expectOddParity(expected, dataPositions: 17...24, parityPosition: 54, dataOnes: yearOnes)
  expectOddParity(expected, dataPositions: 25...35, parityPosition: 55, dataOnes: monthDayOnes)
  expectOddParity(expected, dataPositions: 36...38, parityPosition: 56, dataOnes: weekdayOnes)
  expectOddParity(expected, dataPositions: 39...51, parityPosition: 57, dataOnes: timeOnes)
}

@Test(
  "MSF expected Summer Time distinguishes GMT, BST and disabled prediction",
  arguments: [
    (true, false, Optional(false)), (true, true, true),
    (false, false, nil), (false, true, nil),
  ])
func expectedFrameSummerTime(
  _ predictSummerTime: Bool, _ summerTime: Bool, _ b58: Bool?
) {
  let expected = MSFExpectedFrame(
    calendarDateTime: expectedCalendar(summerTime: summerTime),
    predictSummerTime: predictSummerTime)
  #expect(expected.bit(at: 58, channel: .b) == b58)
}

@Test("Disabling MSF Summer Time prediction changes only B58", arguments: [false, true])
func expectedFrameDisabledSummerTimeIsolation(_ summerTime: Bool) {
  let calendar = expectedCalendar(summerTime: summerTime)
  let enabled = MSFExpectedFrame(calendarDateTime: calendar, predictSummerTime: true)
  let disabled = MSFExpectedFrame(calendarDateTime: calendar, predictSummerTime: false)
  #expect(enabled.bit(at: 58, channel: .b) == summerTime)
  #expect(disabled.bit(at: 58, channel: .b) == nil)
  for position in 17...59 {
    #expect(disabled.bit(at: position, channel: .a) == enabled.bit(at: position, channel: .a))
    if position != 58 {
      #expect(
        disabled.bit(at: position, channel: .b) == enabled.bit(at: position, channel: .b))
    }
  }
}

@Test("MSF expected frame predicts Summer Time by default", arguments: [false, true])
func expectedFrameDefaultSummerTimePrediction(_ summerTime: Bool) {
  let expected = MSFExpectedFrame(calendarDateTime: expectedCalendar(summerTime: summerTime))
  #expect(expected.bit(at: 58, channel: .b) == summerTime)
}

@Test("Changing the MSF calendar Summer Time flag changes only B58")
func expectedFrameCalendarSummerTimeIsolation() {
  let gmt = MSFExpectedFrame(calendarDateTime: expectedCalendar(summerTime: false))
  let bst = MSFExpectedFrame(calendarDateTime: expectedCalendar(summerTime: true))
  for position in 17...59 {
    #expect(gmt.bit(at: position, channel: .a) == bst.bit(at: position, channel: .a))
    if position != 58 {
      #expect(gmt.bit(at: position, channel: .b) == bst.bit(at: position, channel: .b))
    }
  }
  #expect(gmt.bit(at: 58, channel: .b) == false)
  #expect(bst.bit(at: 58, channel: .b) == true)
}

@Test("MSF expected frame distinguishes explicit false values from unmodelled bits")
func expectedFrameFalseAndUnmodelled() {
  let expected = MSFExpectedFrame(calendarDateTime: expectedCalendar(summerTime: false))
  #expect(expected.bit(at: 17, channel: .a) == false)
  #expect(expected.bit(at: 17, channel: .b) == nil)
  #expect(expected.bit(at: 54, channel: .a) == true)
  #expect(expected.bit(at: 54, channel: .b) == false)
  #expect(expected.bit(at: 58, channel: .b) == false)
  #expect(expected.bit(at: 59, channel: .a) == false)
  #expect(expected.bit(at: 59, channel: .b) == nil)
}

@Test(
  "MSF expected frame models all A positions and only selected B positions",
  arguments: 17...59, [false, true])
func expectedFrameModelledPositions(_ position: Int, _ predictSummerTime: Bool) {
  let expected = MSFExpectedFrame(
    calendarDateTime: expectedCalendar(), predictSummerTime: predictSummerTime)
  #expect(expected.bit(at: position, channel: .a) != nil)
  let modelledB = (54...57).contains(position) || (position == 58 && predictSummerTime)
  #expect((expected.bit(at: position, channel: .b) != nil) == modelledB)
}

@Test(
  "MSF expected frame rejects out-of-range lookups on both channels",
  arguments: [Int.min, -1, 0, 16, 60, 61, Int.max])
func expectedFrameOutOfRange(_ position: Int) {
  let expected = MSFExpectedFrame(calendarDateTime: expectedCalendar())
  #expect(expected.bit(at: position, channel: .a) == nil)
  #expect(expected.bit(at: position, channel: .b) == nil)
}

@Test(
  "MSF expected frame encodes the supplied minute independently of seconds",
  arguments: [0, 1, 59])
func expectedFrameSecondsDoNotChangeBits(_ second: Int) {
  let expected = MSFExpectedFrame(calendarDateTime: expectedCalendar(second: second))
  let minute = MSFExpectedFrame(calendarDateTime: expectedCalendar(second: 0))
  for position in 17...59 {
    #expect(expected.bit(at: position, channel: .a) == minute.bit(at: position, channel: .a))
    #expect(expected.bit(at: position, channel: .b) == minute.bit(at: position, channel: .b))
  }
}

@Test(
  "MSF encoder and decoder agree on complete independently specified calendars",
  arguments: [
    (2026, 9, 29, 2, 17, 42, true, UInt64(0x132_694b_c27e), UInt64(0x06)),
    (2026, 9, 30, 3, 13, 26, true, UInt64(0x132_7069_a67e), UInt64(0x1e)),
    (2000, 1, 1, 6, 0, 0, false, UInt64(0x41c0_007e), UInt64(0x3c)),
    (2099, 12, 31, 4, 23, 59, false, UInt64(0x4cc_b191_d97e), UInt64(0x20)),
  ])
func expectedFrameDecodeRoundTrip(
  _ year: Int, _ month: Int, _ day: Int, _ weekday: Int,
  _ hour: Int, _ minute: Int, _ summerTime: Bool,
  _ aBits: UInt64, _ bBits: UInt64
) {
  let calendar = expectedCalendar(
    year: year, month: month, day: day, weekday: weekday,
    hour: hour, minute: minute, summerTime: summerTime)
  let frame = packExpectedFrame(MSFExpectedFrame(calendarDateTime: calendar))
  #expect(frame.aBits == aBits)
  #expect(frame.bBits == bBits)
  let result = frame.decode()
  #expect(result.decodeStatus == .valid)
  #expect(result.calendarDateTime?.year == year)
  #expect(result.calendarDateTime?.month == month)
  #expect(result.calendarDateTime?.dayOfMonth == day)
  #expect(result.calendarDateTime?.dayOfWeek == weekday)
  #expect(result.calendarDateTime?.hour == hour)
  #expect(result.calendarDateTime?.minute == minute)
  #expect(result.calendarDateTime?.second == 0)
  // The decoder's calendar flag is neutral; received B58 remains separate.
  #expect(result.calendarDateTime?.timeZone == nil)
  #expect(frame.summerTime == summerTime)
  #expect(result.calendarDateTime?.settingTimeZone(summerTime ? .bst : .gmt) == calendar)
}

private func expectedCalendar(
  year: Int = 2026, month: Int = 9, day: Int = 29, weekday: Int = 2,
  hour: Int = 17, minute: Int = 42, second: Int = 0, summerTime: Bool = true
) -> CalendarDateTimeComponents {
  CalendarDateTimeComponents(
    year: year, month: month, dayOfMonth: day, dayOfWeek: weekday,
    hour: hour, minute: minute, second: second, timeZone: (summerTime ? .bst : .gmt))
}

private func expectOddParity(
  _ expected: MSFExpectedFrame, dataPositions: ClosedRange<Int>, parityPosition: Int,
  dataOnes: Int
) {
  var ones = 0
  for position in dataPositions {
    if expected.bit(at: position, channel: .a) == true { ones += 1 }
  }
  let parity = expected.bit(at: parityPosition, channel: .b)
  #expect(ones == dataOnes)
  #expect(parity == (dataOnes % 2 == 0))
  #expect((ones + (parity == true ? 1 : 0)) % 2 == 1)
}

private func packExpectedFrame(_ expected: MSFExpectedFrame) -> MSFCompletedFrame {
  var aBits: UInt64 = 0
  var bBits: UInt64 = 0
  // These round trips predict B58 and use dates away from a time-change warning.
  // Unmodelled B positions are transmitted as zero in these fixtures.
  for position in 17...59 {
    let mask = UInt64(1) << (59 - position)
    if expected.bit(at: position, channel: .a) == true { aBits |= mask }
    if expected.bit(at: position, channel: .b) == true { bBits |= mask }
  }
  return MSFCompletedFrame(aBits: aBits, bBits: bBits, dataCount: 59, hasOpeningMarker: true)
}
