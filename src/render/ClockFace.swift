//
//  ClockFace.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-02.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

protocol ClockFace {

  func render(
    into drawingContext: inout DrawingContext,
    displaySnapshot: MSFDisplaySnapshot
  ) -> Bool
}

struct RenderDeadline {
  let timeUs: UInt64

  var hasExpired: Bool { time_us_64() >= self.timeUs }

  func hasExpired(at timeUs: UInt64) -> Bool {
    timeUs >= self.timeUs
  }

  static let distant = RenderDeadline(timeUs: UInt64.max)
}
