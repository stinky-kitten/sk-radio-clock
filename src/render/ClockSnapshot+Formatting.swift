//
//  ClockSnapshot+Formatting.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-11-02.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

enum ClockDisplayPolicy {
  case evidence
  case clock
}

extension ClockSnapshot {
  func unicodeValuesFor24HourTime(
    policy: ClockDisplayPolicy,
    into bytes: inout InlineArray<5, UInt32>
  ) {

    let unknown: UInt32 = 0x003F
    var output = bytes.mutableSpan

    if shouldDisplay(clockState.hour, policy: policy),
      let hour = calendarDateTime.hour
    {
      output[0] = digitCode(forNumeral: hour / 10)
      output[1] = digitCode(forNumeral: hour % 10)
    } else {
      output[0] = unknown
      output[1] = unknown
    }

    output[2] = 0xA789  // Special colon

    if shouldDisplay(clockState.minute, policy: policy),
      let minute = calendarDateTime.minute
    {
      output[3] = digitCode(forNumeral: minute / 10)
      output[4] = digitCode(forNumeral: minute % 10)
    } else {
      output[3] = unknown
      output[4] = unknown
    }
  }

  // At most 12 ASCII bytes; no String construction or allocation in rendering.
  func unicodeValuesForDateMonthYear(
    policy: ClockDisplayPolicy,
    separator: UInt32 = 0x20,
    numericMonth: Bool = false,
    into bytes: inout InlineArray<12, UInt32>
  ) -> Int {
    var output = bytes.mutableSpan

    let day = shouldDisplay(clockState.dayOfMonth, policy: policy) ? calendarDateTime.dayOfMonth : nil
    let unknown: UInt32 = 0x003F

    output[0] = day != nil ? digitCode(forNumeral: day! / 10) : unknown
    output[1] = day != nil ? digitCode(forNumeral: day! % 10) : unknown

    output[2] = separator

    let monthLength: Int
    if numericMonth {
      let month = shouldDisplay(clockState.month, policy: policy) ? calendarDateTime.month : nil
      output[3] = month != nil ? digitCode(forNumeral: month! / 10) : unknown
      output[4] = month != nil ? digitCode(forNumeral: month! % 10) : unknown
      monthLength = 2
    } else {
      let month = (shouldDisplay(clockState.month, policy: policy) ? calendarDateTime.shortMonth : nil) ?? "???"
      monthLength = month.withUTF8Buffer { name in
        for index in 0..<name.count { output[3 + index] = UInt32(name[index]) }
        return name.count
      }
    }
    output[3 + monthLength] = separator

    let year = shouldDisplay(clockState.year, policy: policy) ? calendarDateTime.year : nil

    output[4 + monthLength] = year != nil ? digitCode(forNumeral: year! / 1000) : unknown
    output[5 + monthLength] = year != nil ? digitCode(forNumeral: year! / 100 % 10) : unknown
    output[6 + monthLength] = year != nil ? digitCode(forNumeral: year! / 10 % 10) : unknown
    output[7 + monthLength] = year != nil ? digitCode(forNumeral: year! % 10) : unknown

    return 8 + monthLength
  }

  private func digitCode(forNumeral numeral: Int) -> UInt32 {
    48 + UInt32(numeral)
  }

  private func shouldDisplay(_ state: EpistemicState, policy: ClockDisplayPolicy) -> Bool {
    switch policy {
    case .evidence:
      state != .unknown

    case .clock:
      hasAcquiredTime || state != .unknown
    }
  }
}
