//
//  TimeZone.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-29.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

enum TimeZone: Equatable {
  case gmt
  case bst

  var secondsFromGMT: Int {
    switch self {
    case .gmt: 0
    case .bst: 3_600
    }
  }

  var abbreviation: StaticString {
    switch self {
    case .gmt: "GMT"
    case .bst: "BST"
    }
  }
}
