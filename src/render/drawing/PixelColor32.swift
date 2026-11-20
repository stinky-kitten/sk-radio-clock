//
//  PixelColor32.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-02.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct PixelColor32: Equatable {
  let rawValue: UInt32

  init(rawValue: UInt32) { self.rawValue = rawValue }

  static let transparent = PixelColor32(rawValue: 0)

  init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 0xff) {
    self.rawValue =
      (UInt32(alpha) << 24) | (UInt32(red) << 16) | (UInt32(green) << 8) | UInt32(blue)
  }

  init(red: UInt32, green: UInt32, blue: UInt32, alpha: UInt32 = 0xff) {
    self.rawValue = (alpha << 24) | (red << 16) | (green << 8) | blue
  }

  static let black = PixelColor32(red: UInt32(0x00), green: UInt32(0x00), blue: UInt32(0x00))
  static let white = PixelColor32(red: UInt32(0xff), green: UInt32(0xff), blue: UInt32(0xff))
  static let gray = PixelColor32(red: UInt32(0x80), green: UInt32(0x80), blue: UInt32(0x80))
  static let darkGray = PixelColor32(red: UInt32(0x20), green: UInt32(0x20), blue: UInt32(0x20))
  static let lightGray = PixelColor32(red: UInt32(0xc0), green: UInt32(0xc0), blue: UInt32(0xc0))

  static let red = PixelColor32(red: UInt32(0xff), green: UInt32(0x00), blue: UInt32(0x00))
  static let green = PixelColor32(red: UInt32(0x00), green: UInt32(0xff), blue: UInt32(0x00))
  static let blue = PixelColor32(red: UInt32(0x00), green: UInt32(0x00), blue: UInt32(0xff))

  static let darkGreen = PixelColor32(red: UInt32(0x00), green: UInt32(0x0f), blue: UInt32(0x00))

  static let yellow = PixelColor32(red: UInt32(0xff), green: UInt32(0xff), blue: UInt32(0x00))
  static let magenta = PixelColor32(red: UInt32(0xff), green: UInt32(0x00), blue: UInt32(0xff))
  static let cyan = PixelColor32(red: UInt32(0x00), green: UInt32(0xff), blue: UInt32(0xff))

  static let orange = PixelColor32(red: UInt32(0xff), green: UInt32(0x60), blue: UInt32(0x00))
  static let amber = PixelColor32(red: UInt32(0xff), green: UInt32(0xc0), blue: UInt32(0x00))
  static let purple = PixelColor32(red: UInt32(0x80), green: UInt32(0x00), blue: UInt32(0x80))

  /// Converts to opaque XRGB8888, discarding alpha.
  var xrgb8888: UInt32 { (rawValue & 0x00ff_ffff) | 0xff00_0000 }

  var red: UInt32 { (rawValue >> 16) & 0xff }
  var green: UInt32 { (rawValue >> 8) & 0xff }
  var blue: UInt32 { rawValue & 0xff }
  var alpha: UInt32 { (rawValue >> 24) & 0xff }
}
