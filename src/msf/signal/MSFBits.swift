//
//  MSFBits.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-09-25.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct MSFBits: Equatable {
  let a: Bool
  let b: Bool

  subscript(channel: MSFChannel) -> Bool {
    switch channel {
    case .a: a
    case .b: b
    }
  }
}
