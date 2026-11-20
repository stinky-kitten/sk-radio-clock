//
//  MSFTime.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-06.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

typealias MSFTime = UInt64

private let msfTimeTolerance: MSFTime = 30_000

extension MSFTime {
  func isWithinTolerance(of time: MSFTime) -> Bool {
    if self >= time {
      return self - time <= msfTimeTolerance
    } else {
      return time - self <= msfTimeTolerance
    }
  }
}
