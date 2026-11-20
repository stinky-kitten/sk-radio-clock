//
//  MSFTimeTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-12.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

@Test("MSF time tolerance")
func timeTolerance() {
  let reference: MSFTime = 100_000

  // Exact match
  #expect(reference.isWithinTolerance(of: 100_000))

  // Inside tolerance
  #expect(reference.isWithinTolerance(of: 80_000))
  #expect(reference.isWithinTolerance(of: 120_000))

  // Exactly at the boundary
  #expect(reference.isWithinTolerance(of: 70_000))
  #expect(reference.isWithinTolerance(of: 130_000))

  // Just outside the boundary
  #expect(!reference.isWithinTolerance(of: 69_999))
  #expect(!reference.isWithinTolerance(of: 130_001))
}

@Test("MSF time tolerance at integer limits")
func timeToleranceLimits() {
  #expect(MSFTime.zero.isWithinTolerance(of: 30_000))
  #expect(!MSFTime.zero.isWithinTolerance(of: 30_001))

  #expect(
    MSFTime.max.isWithinTolerance(
      of: MSFTime.max - 30_000
    ))

  #expect(!MSFTime.max.isWithinTolerance(of: 0))
}
