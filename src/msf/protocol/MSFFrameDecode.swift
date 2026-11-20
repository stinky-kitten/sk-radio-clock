//
//  MSFFrameDecode.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-09-28.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct MSFFrameDecode {
  let decodeStatus: MSFDecodeStatus
  let calendarDateTime: CalendarDateTimeComponents?

  init(decodeStatus: MSFDecodeStatus, calendarDateTime: CalendarDateTimeComponents? = nil) {
    self.decodeStatus = decodeStatus
    self.calendarDateTime = calendarDateTime
  }
}

enum MSFDecodeStatus: UInt8 {
  case valid
  case insufficientData
  case invalidFrameLength
  case missingData
  case invalidIdentifier
  case parityYear
  case parityMonthDay
  case parityDayOfWeek
  case parityHourMinute
  case invalidYear
  case invalidMonth
  case invalidDayOfMonth
  case invalidDayOfWeek
  case invalidHour
  case invalidMinute
}
