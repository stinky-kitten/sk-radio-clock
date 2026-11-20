//
//  ClockSnapshot.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-05.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct ClockSnapshot {
  let calendarDateTime: CalendarDateTimeComponents
  let clockState: ClockState
  // Phase within calendarDateTime.second, derived from the model minute anchor.
  let subsecondMicroseconds: UInt32
  let hasSecondTiming: Bool
  // The model has accepted a calendar estimate and monotonic anchor. This says
  // nothing about current radio confidence or whether acquisition used a fully
  // confirmed frame rather than a supported partial handoff.
  let hasAcquiredTime: Bool

  var hasHour: Bool { hasAcquiredTime || clockState.hour != .unknown }
  var hasMinute: Bool { hasAcquiredTime || clockState.minute != .unknown }

  init(
    calendarDateTime: CalendarDateTimeComponents, clockState: ClockState,
    subsecondMicroseconds: UInt32 = 0, hasSecondTiming: Bool = false,
    hasAcquiredTime: Bool = false
  ) {
    self.calendarDateTime = calendarDateTime
    self.clockState = clockState
    self.subsecondMicroseconds = subsecondMicroseconds
    self.hasSecondTiming = hasSecondTiming
    self.hasAcquiredTime = hasAcquiredTime
  }

  static let unknown = ClockSnapshot(
    calendarDateTime: CalendarDateTimeComponents(
      year: nil, month: nil, dayOfMonth: nil, dayOfWeek: nil,
      hour: nil, minute: nil, second: nil, timeZone: nil),
    clockState: .unknown)
}

extension ClockSnapshot {
  init?(instant: UTCInstant, timeZone: TimeZoneConfiguration) {
    guard
      let calendar = CalendarDateTimeComponents(
        instant: instant,
        configuration: timeZone
      )
    else { return nil }

    self.init(
      calendarDateTime: calendar,
      clockState: ClockState(
        year: .supported,
        month: .supported,
        dayOfMonth: .supported,
        dayOfWeek: .supported,
        hour: .supported,
        minute: .supported,
        timeZone: .supported
      ),
      subsecondMicroseconds: instant.nanoseconds / 1_000,
      hasSecondTiming: true,
      hasAcquiredTime: true
    )
  }
}
