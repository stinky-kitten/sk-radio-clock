//
//  MSFStructureAnalysis.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-06.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct MSFStructureAnalysis: Equatable {
  let yearParity: MSFStructureResult
  let monthDayParity: MSFStructureResult
  let dayOfWeekParity: MSFStructureResult
  let hourMinuteParity: MSFStructureResult
  let fixedIdentifier: MSFStructureResult
}

enum MSFStructureResult: Equatable {
  case valid
  case invalid
  case indeterminate
}
