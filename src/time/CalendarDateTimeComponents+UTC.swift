//
//  CalendarDateTimeComponents+UTC.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-30.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

#if SWIFT_PACKAGE
  #if canImport(Darwin)
    import Darwin
  #else
    import Glibc
  #endif
#endif

extension CalendarDateTimeComponents {
  init?(instant: UTCInstant, configuration: TimeZoneConfiguration) {
    guard instant.nanoseconds < 1_000_000_000,
      var seconds = time_t(exactly: instant.unixSeconds)
    else { return nil }

    var calendar = tm()
    guard localtime_r(&seconds, &calendar) != nil else { return nil }

    let timeZone: TimeZone

    if calendar.tm_isdst == 0 {
      timeZone = configuration.standard
    } else if calendar.tm_isdst > 0,
      let daylight = configuration.daylight
    {
      timeZone = daylight
    } else {
      return nil
    }

    self.init(
      year: Int(calendar.tm_year) + 1900,
      month: Int(calendar.tm_mon) + 1,
      dayOfMonth: Int(calendar.tm_mday),
      dayOfWeek: Int(calendar.tm_wday),
      hour: Int(calendar.tm_hour),
      minute: Int(calendar.tm_min),
      second: Int(calendar.tm_sec),
      timeZone: timeZone
    )
  }
}
