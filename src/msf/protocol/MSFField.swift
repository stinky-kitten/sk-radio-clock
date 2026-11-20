//
//  MSFField.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-09-30.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

enum MSFField {
  case year
  case month
  case dayOfMonth
  case dayOfWeek
  case hour
  case minute

  var positions: ClosedRange<Int> {
    switch self {
    case .year: 17...24
    case .month: 25...29
    case .dayOfMonth: 30...35
    case .dayOfWeek: 36...38
    case .hour: 39...44
    case .minute: 45...51
    }
  }
}
