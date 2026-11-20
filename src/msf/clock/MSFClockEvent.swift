//
//  MSFClockEvent.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-06.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

enum MSFClockEvent: Equatable {
  case unacquired
  case acquired(CalendarDateTimeComponents)
  case acquiredFromPartial(CalendarDateTimeComponents)
  case updated(
    CalendarDateTimeComponents, missedMinutes: UInt64,
    contradictions: UInt8, validatedGroups: UInt8)
  case corroborated(CalendarDateTimeComponents)
  case resynchronised(expected: CalendarDateTimeComponents, received: CalendarDateTimeComponents)
  case offGrid(phaseErrorUs: Int64)
  case stale
}
