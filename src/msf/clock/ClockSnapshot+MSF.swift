//
//  ClockSnapshot+MSF.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-29.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension ClockSnapshot {
  /// Add scanner marker timing only when no model/acquisition timing exists.
  /// A second-start phase alone cannot identify the second within the minute.
  func withSecondTiming(at now: MSFTime, minuteMarkerTime: MSFTime?) -> Self {
    guard !hasSecondTiming, let minuteMarkerTime, now >= minuteMarkerTime else { return self }
    let elapsed = (now - minuteMarkerTime) % MSFMinuteGrid.durationUs
    return Self(
      calendarDateTime: calendarDateTime.with(second: Int(elapsed / 1_000_000)), clockState: clockState,
      subsecondMicroseconds: UInt32(elapsed % 1_000_000), hasSecondTiming: true, hasAcquiredTime: hasAcquiredTime)
  }
}
