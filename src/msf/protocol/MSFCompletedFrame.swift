//
//  MSFCompletedFrame.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-06.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// Packed data pairs immediately preceding a validated closing marker. Bit zero
// is the final pair (*59); bits 42...0 are the invariant *17...*59 suffix.
struct MSFCompletedFrame {
  let aBits: UInt64
  let bBits: UInt64
  let unknownBits: UInt64
  let dataCount: Int
  let hasOpeningMarker: Bool
  let closingMarkerTime: UInt64

  init(
    aBits: UInt64, bBits: UInt64, unknownBits: UInt64 = 0,
    dataCount: Int, hasOpeningMarker: Bool, closingMarkerTime: UInt64 = 0
  ) {
    self.aBits = aBits
    self.bBits = bBits
    self.unknownBits = unknownBits
    self.dataCount = dataCount
    self.hasOpeningMarker = hasOpeningMarker
    self.closingMarkerTime = closingMarkerTime
  }

  func logicalFrame() -> MSFLogicalFrame? {
    MSFLogicalFrame(completedFrame: self)
  }

  var summerTime: Bool? {
    logicalFrame()?.bit(at: MSFLogicalLayout.summerTimePosition, channel: .b)
  }

  func decode() -> MSFFrameDecode {
    guard let logical = logicalFrame() else {
      return MSFFrameDecode(decodeStatus: .insufficientData)
    }
    if hasOpeningMarker && !(58...60).contains(dataCount) {
      return MSFFrameDecode(decodeStatus: .invalidFrameLength)
    }
    if logical.hasUnknownPosition {
      return MSFFrameDecode(decodeStatus: .missingData)
    }

    let structure = logical.analyze()
    guard structure.fixedIdentifier == .valid else {
      return MSFFrameDecode(decodeStatus: .invalidIdentifier)
    }
    guard structure.yearParity == .valid else {
      return MSFFrameDecode(decodeStatus: .parityYear)
    }
    guard structure.monthDayParity == .valid else {
      return MSFFrameDecode(decodeStatus: .parityMonthDay)
    }
    guard structure.dayOfWeekParity == .valid else {
      return MSFFrameDecode(decodeStatus: .parityDayOfWeek)
    }
    guard structure.hourMinuteParity == .valid else {
      return MSFFrameDecode(decodeStatus: .parityHourMinute)
    }

    guard let year = logical.bcdValue(for: .year),
      Self.validYearRange.contains(year)
    else {
      return MSFFrameDecode(decodeStatus: .invalidYear)
    }

    guard let month = logical.bcdValue(for: .month),
      Self.validMonthRange.contains(month)
    else { return MSFFrameDecode(decodeStatus: .invalidMonth) }

    guard let dayOfMonth = logical.bcdValue(for: .dayOfMonth),
      Self.validDayOfMonthRange.contains(dayOfMonth)
    else {
      return MSFFrameDecode(decodeStatus: .invalidDayOfMonth)
    }

    guard
      let dayOfWeek = logical.bcdValue(for: .dayOfWeek),
      Self.validDayOfWeekRange.contains(dayOfWeek)
    else {
      return MSFFrameDecode(decodeStatus: .invalidDayOfWeek)
    }

    guard let hour = logical.bcdValue(for: .hour),
      Self.validHourRange.contains(hour)
    else {
      return MSFFrameDecode(decodeStatus: .invalidHour)
    }

    guard let minute = logical.bcdValue(for: .minute),
      Self.validMinuteRange.contains(minute)
    else {
      return MSFFrameDecode(decodeStatus: .invalidMinute)
    }

    let fullYear = 2000 + Int(year)
    guard let weekday = CalendarDateTimeComponents.weekday(year: fullYear, month: Int(month), day: Int(dayOfMonth))
    else { return MSFFrameDecode(decodeStatus: .invalidDayOfMonth) }
    guard weekday == Int(dayOfWeek) else { return MSFFrameDecode(decodeStatus: .invalidDayOfWeek) }

    return MSFFrameDecode(
      decodeStatus: .valid,
      calendarDateTime: CalendarDateTimeComponents(
        year: fullYear, month: Int(month), dayOfMonth: Int(dayOfMonth),
        dayOfWeek: Int(dayOfWeek), hour: Int(hour), minute: Int(minute),
        second: 0, timeZone: nil)
    )
  }
}

extension MSFCompletedFrame {
  static let validYearRange: ClosedRange<UInt8> = 0...99
  static let validMonthRange: ClosedRange<UInt8> = 1...12
  static let validDayOfMonthRange: ClosedRange<UInt8> = 1...31
  static let validDayOfWeekRange: ClosedRange<UInt8> = 0...6
  static let validHourRange: ClosedRange<UInt8> = 0...23
  static let validMinuteRange: ClosedRange<UInt8> = 0...59
}
