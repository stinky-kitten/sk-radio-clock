//
//  CalendarDateTimeComponents.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-29.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// Calendar date/time components; individual fields may be unknown.
// Weekdays use 0=Sunday. Calendar advancement requires complete date
// and minute fields and preserves the time zone without applying
// daylight-saving transition rules.
// Time-zone transition policy is outside this arithmetic helper.
struct CalendarDateTimeComponents: Equatable {
  let year: Int?
  let month: Int?
  let dayOfMonth: Int?
  let dayOfWeek: Int?
  let hour: Int?
  let minute: Int?
  let second: Int?
  let timeZone: TimeZone?

  func advanced(byMinutes minuteCount: UInt64) -> Self? {
    guard let year, let month, let dayOfMonth,
      let dayOfWeek, let hour, let minute
    else {
      return nil
    }

    let minuteOfDay = hour * 60 + minute
    let remainder = Int(minuteCount % 1_440)
    let combined = minuteOfDay + remainder
    var days = minuteCount / 1_440 + UInt64(combined / 1_440)
    let nextMinuteOfDay = combined % 1_440
    var nextYear = year
    var nextMonth = month
    var nextDay = dayOfMonth
    var nextWeekday = dayOfWeek

    while days > 0 {
      nextWeekday = (nextWeekday + 1) % 7
      if nextDay < Self.daysInMonth(nextMonth, year: nextYear) {
        nextDay += 1
      } else {
        nextDay = 1
        if nextMonth == 12 {
          nextMonth = 1
          // The present model assumes the 2000...2099 century.
          nextYear = nextYear + 1
        } else {
          nextMonth += 1
        }
      }
      days -= 1
    }
    return Self(
      year: nextYear, month: nextMonth, dayOfMonth: nextDay,
      dayOfWeek: nextWeekday, hour: nextMinuteOfDay / 60,
      minute: nextMinuteOfDay % 60, second: 0, timeZone: timeZone)
  }

  func settingTimeZone(_ value: TimeZone?) -> Self {
    Self(
      year: year, month: month, dayOfMonth: dayOfMonth, dayOfWeek: dayOfWeek,
      hour: hour, minute: minute, second: second, timeZone: value)
  }

  // Calendar constraints for initial acquisition. 1 January 2000 was Saturday.
  static func weekday(year: Int, month: Int, day: Int) -> Int? {
    guard (2000...2099).contains(year), (1...12).contains(month),
      (1...daysInMonth(month, year: year)).contains(day)
    else { return nil }
    let yearOffset = year - 2000
    var days = 365 * yearOffset + (yearOffset + 3) / 4 + day - 1
    for previousMonth in 1..<month {
      days += daysInMonth(previousMonth, year: year)
    }
    return (6 + days) % 7
  }

  static func daysInMonth(_ month: Int, year: Int) -> Int {
    switch month {
    case 4, 6, 9, 11: 30
    case 2: isLeapYear(year) ? 29 : 28
    default: 31
    }
  }

  private static func isLeapYear(_ fullYear: Int) -> Bool {
    fullYear % 4 == 0 && (fullYear % 100 != 0 || fullYear % 400 == 0)
  }
}

extension CalendarDateTimeComponents {
  func with(second: Int) -> Self {
    Self(
      year: year,
      month: month,
      dayOfMonth: dayOfMonth,
      dayOfWeek: dayOfWeek,
      hour: hour,
      minute: minute,
      second: second,
      timeZone: timeZone
    )
  }
}
