//
//  MSFExpectedFrame.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-09-30.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct MSFExpectedSecond: Equatable {
  var a: Bool?
  var b: Bool?
}

// A concrete prediction for the understood *17...*59 bits. Nil here means
// "not modelled", distinct from a nil received MSFSecond (missing reception).
// B58 is predicted only when enabled and timeZone is known: BST=true, GMT=false.
// An unknown zone leaves B58 unmodelled; it is never substituted with GMT.
struct MSFExpectedFrame {
  private var seconds: InlineArray<43, MSFExpectedSecond> =
    .init(repeating: MSFExpectedSecond(a: nil, b: nil))

  init(calendarDateTime: CalendarDateTimeComponents, predictSummerTime: Bool = true) {
    if let year = calendarDateTime.year {
      setBCD(forValue: UInt8(year - 2000), inField: .year)
    }
    if let month = calendarDateTime.month {
      setBCD(forValue: UInt8(month), inField: .month)
    }
    if let dayOfMonth = calendarDateTime.dayOfMonth {
      setBCD(forValue: UInt8(dayOfMonth), inField: .dayOfMonth)
    }
    if let dayOfWeek = calendarDateTime.dayOfWeek {
      setBCD(forValue: UInt8(dayOfWeek), inField: .dayOfWeek)
    }
    if let hour = calendarDateTime.hour {
      setBCD(forValue: UInt8(hour), inField: .hour)
    }
    if let minute = calendarDateTime.minute {
      setBCD(forValue: UInt8(minute), inField: .minute)
    }

    let identifier = MSFLogicalLayout.identifier
    for position in identifier {
      set(position: position, channel: .a, to: MSFLogicalLayout.identifierBit(at: position))
    }

    setOddParity(forGroup: MSFLogicalLayout.yearParity)
    setOddParity(forGroup: MSFLogicalLayout.monthDayParity)
    setOddParity(forGroup: MSFLogicalLayout.dayOfWeekParity)
    setOddParity(forGroup: MSFLogicalLayout.hourMinuteParity)

    if predictSummerTime, let timeZone = calendarDateTime.timeZone {
      set(
        position: MSFLogicalLayout.summerTimePosition,
        channel: .b,
        to: timeZone == .bst
      )
    }
  }

  func bit(at position: Int, channel: MSFChannel) -> Bool? {
    guard let index = MSFLogicalFrame.index(forLogicalPosition: position) else { return nil }
    switch channel {
    case .a: return seconds[index].a
    case .b: return seconds[index].b
    }
  }

  private mutating func set(position: Int, channel: MSFChannel, to value: Bool) {
    guard let index = MSFLogicalFrame.index(forLogicalPosition: position) else { return }
    var second = seconds[index]
    switch channel {
    case .a: second.a = value
    case .b: second.b = value
    }
    seconds[index] = second
  }

  private static func packedBCD(_ value: UInt8) -> UInt8 {
    ((value / 10) << 4) | (value % 10)
  }

  private mutating func setBCD(forValue value: UInt8, inField field: MSFField) {
    let bits = Self.bcdBits(forValue: value, inField: field)

    for position in field.positions {
      let mask = UInt64(1) << (MSFLogicalFrame.logicalRange.upperBound - position)
      set(position: position, channel: .a, to: bits & mask != 0)
    }
  }

  // Positioned bits shared with bounded acquisition-domain generation.
  // The field definition supplies the transmitted width; units use four BCD bits.
  static func bcdBits(forValue value: UInt8, inField field: MSFField) -> UInt64 {
    UInt64(packedBCD(value))
      << (MSFLogicalFrame.logicalRange.upperBound - field.positions.upperBound)
  }

  private mutating func setOddParity(forGroup group: MSFParityGroup) {
    var ones = 0

    for position in group.dataPositions {
      guard let bit = bit(at: position, channel: .a) else { return }
      if bit { ones += 1 }
    }

    set(position: group.parityPosition, channel: .b, to: ones % 2 == 0)
  }
}
