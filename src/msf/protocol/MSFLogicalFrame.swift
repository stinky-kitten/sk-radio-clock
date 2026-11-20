//
//  MSFLogicalFrame.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-09-30.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// The 43 ordinary positions immediately before a genuine closing marker are
// logical MSF seconds *17...*59, regardless of the physical minute length.
struct MSFLogicalFrame {
  static let logicalRange = 17...59
  private var bits: InlineArray<43, MSFBits?> = .init(repeating: nil)

  init?(completedFrame: MSFCompletedFrame) {
    guard completedFrame.dataCount >= Self.logicalRange.count else { return nil }
    for index in 0..<Self.logicalRange.count {
      let offset = Self.logicalRange.count - 1 - index
      let mask = UInt64(1) << offset
      if completedFrame.unknownBits & mask == 0 {
        bits[index] = MSFBits(
          a: completedFrame.aBits & mask != 0,
          b: completedFrame.bBits & mask != 0)
      }
    }
  }

  static func index(forLogicalPosition position: Int) -> Int? {
    guard logicalRange.contains(position) else { return nil }
    return position - logicalRange.lowerBound
  }

  static func packedMask(for positions: ClosedRange<Int>) -> UInt64 {
    let width = positions.upperBound - positions.lowerBound + 1
    return ((UInt64(1) << width) - 1) << (Self.logicalRange.upperBound - positions.upperBound)
  }

  func bits(atLogicalPosition position: Int) -> MSFBits? {
    guard let index = Self.index(forLogicalPosition: position) else {
      return nil
    }
    return bits[index]
  }

  func bit(at position: Int, channel: MSFChannel) -> Bool? {
    bits(atLogicalPosition: position)?[channel]
  }

  func bcdValue(for field: MSFField) -> UInt8? {
    var value: UInt8 = 0
    var digit: UInt8 = 0
    var digitBit: UInt8 = 0
    var multiplier: UInt8 = 1

    for position in field.positions.reversed() {
      guard let bits = bits(atLogicalPosition: position) else {
        return nil
      }

      if bits.a {
        digit |= 1 << digitBit
      }

      digitBit += 1

      if digitBit == 4 {
        guard digit <= 9 else { return nil }

        value += digit * multiplier
        multiplier *= 10
        digit = 0
        digitBit = 0
      }
    }

    if digitBit > 0 {
      guard digit <= 9 else { return nil }
      value += digit * multiplier
    }

    return value
  }

  var hasUnknownPosition: Bool {
    for index in 0..<Self.logicalRange.count {
      if bits[index] == nil { return true }
    }
    return false
  }

  func analyze() -> MSFStructureAnalysis {
    MSFStructureAnalysis(
      yearParity: parity(forGroup: MSFLogicalLayout.yearParity),
      monthDayParity: parity(forGroup: MSFLogicalLayout.monthDayParity),
      dayOfWeekParity: parity(forGroup: MSFLogicalLayout.dayOfWeekParity),
      hourMinuteParity: parity(forGroup: MSFLogicalLayout.hourMinuteParity),
      fixedIdentifier: identifier())
  }

  private func parity(forGroup group: MSFParityGroup) -> MSFStructureResult {
    guard let parityBit = bit(at: group.parityPosition, channel: .b) else {
      return .indeterminate
    }
    var ones = parityBit ? 1 : 0
    for position in group.dataPositions {
      guard let value = bit(at: position, channel: .a) else { return .indeterminate }
      if value { ones += 1 }
    }
    return ones % 2 == 1 ? .valid : .invalid
  }

  private func identifier() -> MSFStructureResult {
    var matches = true
    let positions = MSFLogicalLayout.identifier
    for position in positions {
      guard let value = bit(at: position, channel: .a) else { return .indeterminate }
      if value != MSFLogicalLayout.identifierBit(at: position) {
        matches = false
      }
    }
    return matches ? .valid : .invalid
  }
}
