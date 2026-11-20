//
//  MSFMinuteGrid.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-06.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// Shared by initial acquisition and the running clock. Partial observations
// never move their fixed minute anchor. This 250 ms window is deliberately
// separate from the scanner's pulse and second-phase timing tolerances.
enum MSFMinuteGrid {
  static let durationUs: UInt64 = 60_000_000
  static let toleranceUs: Int64 = 250_000

  static func isAligned(_ error: Int64) -> Bool {
    error >= -toleranceUs && error <= toleranceUs
  }

  static func position(_ elapsed: UInt64) -> (index: UInt64, error: Int64) {
    let whole = elapsed / durationUs
    let remainder = elapsed % durationUs
    if remainder > durationUs / 2 {
      return (whole + 1, Int64(remainder) - Int64(durationUs))
    }
    return (whole, Int64(remainder))
  }
}
