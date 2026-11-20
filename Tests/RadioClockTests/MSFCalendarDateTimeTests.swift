//
//  CalendarDateTimeComponentsTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-13.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

// Expected dates and weekdays are fixed Gregorian-calendar reference values,
// established independently of advanced(byMinutes:) and weekday(year:month:day:).
// Weekday zero is Sunday. Summer Time is a retained value, not inferred from dates.

@Test("MSF calendar equality includes minute, second and Summer Time values")
func calendarDateTimeEquality() {
  let value = calendarValue()
  #expect(value == calendarValue())
  #expect(value != calendarValue(minute: 27))
  #expect(value != calendarValue(second: 1))
  #expect(value != calendarValue(summerTime: false))
}

@Test(
  "MSF calendar advances minutes and hours within a day",
  arguments: [
    (UInt64(0), 13, 26), (1, 13, 27), (8, 13, 34), (33, 13, 59),
    (34, 14, 0), (59, 14, 25), (60, 14, 26), (90, 14, 56), (600, 23, 26),
  ])
func calendarMinuteAdvancement(_ minutes: UInt64, _ hour: Int, _ minute: Int) {
  let original = calendarValue()
  #expect(original.advanced(byMinutes: minutes) == calendarValue(hour: hour, minute: minute))
  #expect(original == calendarValue())
}

@Test(
  "MSF calendar midnight advances each weekday including Saturday to Sunday",
  arguments: [
    (9, 27, 0, 9, 28, 1), (9, 28, 1, 9, 29, 2), (9, 29, 2, 9, 30, 3),
    (9, 30, 3, 10, 1, 4), (10, 1, 4, 10, 2, 5), (10, 2, 5, 10, 3, 6),
    (10, 3, 6, 10, 4, 0),
  ])
func calendarMidnightAndWeekdays(
  _ month: Int, _ day: Int, _ weekday: Int,
  _ nextMonth: Int, _ nextDay: Int, _ nextWeekday: Int
) {
  let original = calendarValue(month: month, day: day, weekday: weekday, hour: 23, minute: 59)
  #expect(
    original.advanced(byMinutes: 1)
      == calendarValue(
        month: nextMonth, day: nextDay, weekday: nextWeekday, hour: 0, minute: 0))
}

@Test(
  "MSF calendar rolls over every thirty-day month",
  arguments: [
    (4, 4, 5, 5), (6, 2, 7, 3), (9, 3, 10, 4), (11, 1, 12, 2),
  ])
func calendarThirtyDayMonths(_ month: Int, _ weekday: Int, _ nextMonth: Int, _ nextWeekday: Int) {
  let original = calendarValue(month: month, day: 30, weekday: weekday, hour: 23, minute: 59)
  #expect(
    original.advanced(byMinutes: 1)
      == calendarValue(
        month: nextMonth, day: 1, weekday: nextWeekday, hour: 0, minute: 0))
}

@Test(
  "MSF calendar rolls over thirty-one-day months",
  arguments: [
    (1, 6, 2, 0), (3, 2, 4, 3), (5, 0, 6, 1),
    (7, 5, 8, 6), (8, 1, 9, 2), (10, 6, 11, 0),
  ])
func calendarThirtyOneDayMonths(_ month: Int, _ weekday: Int, _ nextMonth: Int, _ nextWeekday: Int) {
  let original = calendarValue(month: month, day: 31, weekday: weekday, hour: 23, minute: 59)
  #expect(
    original.advanced(byMinutes: 1)
      == calendarValue(
        month: nextMonth, day: 1, weekday: nextWeekday, hour: 0, minute: 0))
}

@Test(
  "MSF calendar ordinary February ends after day twenty-eight",
  arguments: [
    (2026, 6, 0), (2027, 0, 1), (2029, 3, 4),
  ])
func calendarOrdinaryFebruary(_ year: Int, _ weekday: Int, _ nextWeekday: Int) {
  let original = calendarValue(
    year: year, month: 2, day: 28, weekday: weekday, hour: 23, minute: 59)
  #expect(
    original.advanced(byMinutes: 1)
      == calendarValue(
        year: year, month: 3, day: 1, weekday: nextWeekday, hour: 0, minute: 0))
}

@Test(
  "MSF calendar leap years enter and leave February twenty-nine",
  arguments: [
    (2000, 1, 2, 3), (2004, 6, 0, 1), (2024, 3, 4, 5),
    (2028, 1, 2, 3), (2096, 2, 3, 4),
  ])
func calendarLeapFebruary(_ year: Int, _ february28: Int, _ february29: Int, _ march1: Int) {
  let beforeLeapDay = calendarValue(
    year: year, month: 2, day: 28, weekday: february28, hour: 23, minute: 59)
  #expect(
    beforeLeapDay.advanced(byMinutes: 1)
      == calendarValue(
        year: year, month: 2, day: 29, weekday: february29, hour: 0, minute: 0))
  let endOfLeapDay = calendarValue(
    year: year, month: 2, day: 29, weekday: february29, hour: 23, minute: 59)
  #expect(
    endOfLeapDay.advanced(byMinutes: 1)
      == calendarValue(
        year: year, month: 3, day: 1, weekday: march1, hour: 0, minute: 0))
}

@Test(
  "MSF calendar December thirty-one increments the full year without wrapping",
  arguments: [
    (2000, 0, 2001, 1), (2026, 4, 2027, 5), (2028, 0, 2029, 1), (2099, 4, 2100, 5),
  ])
func calendarYearRollover(_ year: Int, _ weekday: Int, _ nextYear: Int, _ nextWeekday: Int) {
  let original = calendarValue(
    year: year, month: 12, day: 31, weekday: weekday, hour: 23, minute: 59)
  #expect(
    original.advanced(byMinutes: 1)
      == calendarValue(
        year: nextYear, month: 1, day: 1, weekday: nextWeekday, hour: 0, minute: 0))
}

@Test(
  "MSF calendar advances over multiple days, weeks and a leap year",
  arguments: [
    (calendarValue(), UInt64(1_440), calendarValue(month: 10, day: 1, weekday: 4)),
    (calendarValue(), 2_880, calendarValue(month: 10, day: 2, weekday: 5)),
    (calendarValue(), 10_080, calendarValue(month: 10, day: 7, weekday: 3)),
    (calendarValue(), 20_160, calendarValue(month: 10, day: 14, weekday: 3)),
    (
      calendarValue(), 50_000,
      calendarValue(month: 11, day: 4, weekday: 3, hour: 6, minute: 46)
    ),
    (
      calendarValue(hour: 23, minute: 50), 1_455,
      calendarValue(month: 10, day: 2, weekday: 5, hour: 0, minute: 5)
    ),
    (
      calendarValue(year: 2028, month: 2, day: 27, weekday: 0, hour: 22, minute: 50), 4_410,
      calendarValue(year: 2028, month: 3, day: 2, weekday: 4, hour: 0, minute: 20)
    ),
    (
      calendarValue(year: 2000, month: 1, day: 1, weekday: 6, hour: 0, minute: 0), 525_600,
      calendarValue(year: 2000, month: 12, day: 31, weekday: 0, hour: 0, minute: 0)
    ),
    (
      calendarValue(year: 2000, month: 1, day: 1, weekday: 6, hour: 0, minute: 0), 527_040,
      calendarValue(year: 2001, month: 1, day: 1, weekday: 1, hour: 0, minute: 0)
    ),
  ])
func calendarMultipleDays(
  _ original: CalendarDateTimeComponents, _ minutes: UInt64, _ expected: CalendarDateTimeComponents
) {
  #expect(original.advanced(byMinutes: minutes) == expected)
}

@Test(
  "MSF calendar advancement preserves GMT or BST instead of applying transition rules",
  arguments: [UInt64(0), 1, 1_440, 50_000], [false, true])
func calendarSummerTimePreserved(_ minutes: UInt64, _ summerTime: Bool) {
  let original = calendarValue(summerTime: summerTime)
  let result = original.advanced(byMinutes: minutes)
  #expect(result?.timeZone == (summerTime ? .bst : .gmt))
  #expect(original == calendarValue(summerTime: summerTime))
}

@Test(
  "MSF minute advancement resets seconds even when advancing by zero minutes",
  arguments: [0, 1, 17, 59])
func calendarAdvancementSeconds(_ second: Int) {
  let original = calendarValue(second: second)
  #expect(original.advanced(byMinutes: 0) == calendarValue())
  #expect(original.advanced(byMinutes: 1) == calendarValue(minute: 27))
  #expect(original.second == second)
}

@Test(
  "MSF Gregorian weekday helper matches independent reference dates",
  arguments: [
    (2000, 1, 1, 6), (2000, 2, 29, 2), (2026, 2, 28, 6), (2026, 3, 1, 0),
    (2026, 9, 29, 2), (2026, 9, 30, 3), (2026, 10, 3, 6), (2026, 10, 4, 0),
    (2028, 2, 29, 2), (2099, 12, 31, 4),
  ])
func calendarWeekdayReference(_ year: Int, _ month: Int, _ day: Int, _ expected: Int) {
  #expect(CalendarDateTimeComponents.weekday(year: year, month: month, day: day) == expected)
}

@Test(
  "MSF weekday helper rejects invalid dates and years outside its defined century",
  arguments: [
    (0, 1, 1), (1999, 12, 31), (2100, 1, 1), (2026, 0, 1), (2026, 13, 1),
    (2026, 1, 0), (2026, 1, 32), (2026, 2, 29), (2028, 2, 30), (2026, 9, 31),
  ])
func calendarWeekdayInvalidDate(_ year: Int, _ month: Int, _ day: Int) {
  #expect(CalendarDateTimeComponents.weekday(year: year, month: month, day: day) == nil)
}

@Test(
  "MSF calendar month lengths match ordinary Gregorian months",
  arguments: [
    (1, 31), (2, 28), (3, 31), (4, 30), (5, 31), (6, 30),
    (7, 31), (8, 31), (9, 30), (10, 31), (11, 30), (12, 31),
  ])
func calendarMonthLengths(_ month: Int, _ days: Int) {
  #expect(CalendarDateTimeComponents.daysInMonth(month, year: 2026) == days)
}

@Test(
  "MSF calendar leap February includes the Gregorian year 2000",
  arguments: [2000, 2004, 2024, 2028, 2096])
func calendarLeapMonthLength(_ year: Int) {
  #expect(CalendarDateTimeComponents.daysInMonth(2, year: year) == 29)
}

@Test("MSF calendar Summer Time replacement preserves every other field", arguments: [false, true])
func calendarSettingSummerTime(_ summerTime: Bool) {
  let original = calendarValue(second: 17, summerTime: summerTime)
  #expect(
    original.settingTimeZone(!summerTime ? .bst : .gmt)
      == calendarValue(second: 17, summerTime: !summerTime))
  #expect(original == calendarValue(second: 17, summerTime: summerTime))
}

@Test(
  "MSF calendar second replacement preserves the date, minute and Summer Time",
  arguments: [0, 1, 17, 59])
func calendarSettingSecond(_ second: Int) {
  let original = calendarValue(second: 37)
  #expect(original.with(second: second) == calendarValue(second: second))
  #expect(original == calendarValue(second: 37))
}

private func calendarValue(
  year: Int = 2026, month: Int = 9, day: Int = 30, weekday: Int = 3,
  hour: Int = 13, minute: Int = 26, second: Int = 0, summerTime: Bool = true
) -> CalendarDateTimeComponents {
  CalendarDateTimeComponents(
    year: year, month: month, dayOfMonth: day, dayOfWeek: weekday,
    hour: hour, minute: minute, second: second, timeZone: (summerTime ? .bst : .gmt))
}
