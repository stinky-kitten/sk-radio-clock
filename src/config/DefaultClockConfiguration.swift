//
//  DefaultClockConfiguration.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-28.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// Used only when there is no local configuration and wireless support is off.
extension ClockConfiguration {
  static let current = ClockConfiguration(
    timeSource: .msf,
    theme: .standard,
    timeZone: .uk
  )
}
