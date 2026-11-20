//
//  MSFLogicalLayout.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-06.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// The decoder, structural checks, expected-frame encoder, and clock confidence
// projection share these transmitted positions.
enum MSFLogicalLayout {
  static let identifier = 52...59

  static func identifierBit(at position: Int) -> Bool {
    position != identifier.lowerBound && position != identifier.upperBound
  }

  static let yearParity = MSFParityGroup(dataPositions: 17...24, parityPosition: 54)
  static let monthDayParity = MSFParityGroup(dataPositions: 25...35, parityPosition: 55)
  static let dayOfWeekParity = MSFParityGroup(dataPositions: 36...38, parityPosition: 56)
  static let hourMinuteParity = MSFParityGroup(dataPositions: 39...51, parityPosition: 57)

  static let summerTimePosition = 58
}

struct MSFParityGroup {
  let dataPositions: ClosedRange<Int>
  let parityPosition: Int
}
