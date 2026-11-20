//
//  MSFAcquisitionStatus.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-06.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

enum MSFAcquisitionStatus: Equatable {
  case unacquired
  case ambiguous
  case candidate
  case supported
}
