//
//  FloatingPoint.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-11-10.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension BinaryFloatingPoint {
  static var tau: Self { 2 * .pi }
  static var 𝜏: Self { .tau }

  @inline(__always)
  var unitQuantized8: UInt8 { UInt8((self * 255).rounded()) }
}
