//
//  ClockFaceKind.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-23.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

enum ClockFaceKind {
  case analytical
  case analogue
  case digital

  static func initial(for source: TimeSource) -> Self {
    switch source {
    case .msf: .analytical
    case .ntp: .analogue
    }
  }

  func next(for source: TimeSource) -> Self {
    switch source {
    case .msf:
      switch self {
      case .analytical: .analogue
      case .analogue: .digital
      case .digital: .analytical
      }

    case .ntp:
      switch self {
      case .analytical: .analogue
      case .analogue: .digital
      case .digital: .analogue
      }
    }
  }
}
