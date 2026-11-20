//
//  PixelColor32Tests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

@Test(
  "Pixel colours store alpha then red green blue in the packed raw value",
  arguments: [
    (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt32(0x0000_0000), UInt32(0xff00_0000)),
    (0x12, 0x34, 0x56, 0x78, 0x7812_3456, 0xff12_3456),
    (0xff, 0, 0, 0x80, 0x80ff_0000, 0xffff_0000),
    (0, 0xff, 0, 0, 0x0000_ff00, 0xff00_ff00),
    (0, 0, 0xff, 1, 0x0100_00ff, 0xff00_00ff),
    (0xff, 0xff, 0xff, 0xff, 0xffff_ffff, 0xffff_ffff),
  ] as [(UInt8, UInt8, UInt8, UInt8, UInt32, UInt32)])
func pixelColourChannels(
  _ red: UInt8, _ green: UInt8, _ blue: UInt8, _ alpha: UInt8,
  _ raw: UInt32, _ framebuffer: UInt32
) {
  let colour = PixelColor32(red: red, green: green, blue: blue, alpha: alpha)
  #expect(colour.rawValue == raw)
  #expect(colour.xrgb8888 == framebuffer)
  #expect(colour.red == UInt32(red) && colour.green == UInt32(green))
  #expect(colour.blue == UInt32(blue) && colour.alpha == UInt32(alpha))
}

@Test(
  "Pixel framebuffer conversion discards alpha rather than premultiplying colour",
  arguments: [UInt8(0), 1, 127, 128, 254, 255])
func pixelColourOpaqueConversion(_ alpha: UInt8) {
  let colour = PixelColor32(red: 0x12, green: 0x34, blue: 0x56, alpha: alpha)
  #expect(colour.xrgb8888 == 0xff12_3456)
}

@Test("Pixel colours default to full opacity and opaque black is nonzero")
func pixelColourDefaultOpacity() {
  #expect(
    PixelColor32(red: UInt32(0x12), green: UInt32(0x34), blue: UInt32(0x56)).rawValue
      == 0xff12_3456)
  #expect(PixelColor32.black.rawValue == 0xff00_0000)
  #expect(PixelColor32.black.xrgb8888 == 0xff00_0000)
  #expect(PixelColor32.black.xrgb8888 != 0)
  #expect(PixelColor32.white.xrgb8888 == 0xffff_ffff)
}

@Test(
  "Pixel UInt32 components construct the same ARGB representation and extract byte-valued channels",
  arguments: [
    (UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0x0000_0000), UInt32(0xff00_0000)),
    (0x12, 0xa4, 0x56, 0x78, 0x7812_a456, 0xff12_a456),
    (0xff, 0, 0, 0x80, 0x80ff_0000, 0xffff_0000),
    (0, 0xff, 0, 1, 0x0100_ff00, 0xff00_ff00),
    (0, 0, 0xff, 0xfe, 0xfe00_00ff, 0xff00_00ff),
    (0xff, 0xff, 0xff, 0xff, 0xffff_ffff, 0xffff_ffff),
  ] as [(UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)])
func pixelColourWideComponents(
  _ red: UInt32, _ green: UInt32, _ blue: UInt32,
  _ alpha: UInt32, _ raw: UInt32, _ framebuffer: UInt32
) {
  let colour = PixelColor32(red: red, green: green, blue: blue, alpha: alpha)
  #expect(colour.rawValue == raw && colour.xrgb8888 == framebuffer)
  #expect(colour.red == red && colour.green == green && colour.blue == blue && colour.alpha == alpha)
}
