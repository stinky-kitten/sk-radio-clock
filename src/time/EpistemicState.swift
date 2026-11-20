//
//  EpistemicState.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-09-30.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

enum EpistemicState: Equatable {
  case unknown
  case candidate
  case supported
  case confirmed

  var isConfirmed: Bool {
    if case .confirmed = self {
      return true
    }
    return false
  }
}
