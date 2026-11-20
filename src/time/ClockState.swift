//
//  ClockState.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-05.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct ClockState {
  let year: EpistemicState
  let month: EpistemicState
  let dayOfMonth: EpistemicState
  let dayOfWeek: EpistemicState
  let hour: EpistemicState
  let minute: EpistemicState
  let timeZone: EpistemicState

  static let unknown = ClockState(
    year: .unknown, month: .unknown, dayOfMonth: .unknown,
    dayOfWeek: .unknown, hour: .unknown, minute: .unknown,
    timeZone: .unknown
  )
}
