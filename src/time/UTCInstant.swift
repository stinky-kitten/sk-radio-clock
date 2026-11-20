//
//  UTCInstant.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-30.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct UTCInstant {
  let unixSeconds: Int64
  let nanoseconds: UInt32
}

extension UTCInstant {
  init(unixSeconds: Int64) {
    self.unixSeconds = unixSeconds
    self.nanoseconds = 0
  }
}
