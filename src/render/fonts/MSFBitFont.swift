//
//  MSFBitFont.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-09.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

enum MSFBitFont: Font {
  static let ascent = 5
  static let descent = 0
  static let lineHeight = 5

  static let glyphAdvance = 3

  private static let bitmap: InlineArray<60, UInt8> = [
    // 0
    255, 255, 255,
    255, 0, 255,
    255, 0, 255,
    255, 0, 255,
    255, 255, 255,

    // 1
    0, 255, 0,
    255, 255, 0,
    0, 255, 0,
    0, 255, 0,
    255, 255, 255,

    // ?
    255, 255, 255,
    0, 0, 255,
    0, 255, 255,
    0, 0, 0,
    0, 255, 0,

    // M
    255, 0, 255,
    255, 255, 255,
    255, 255, 255,
    255, 0, 255,
    255, 0, 255,
  ]

  static func glyph(for scalar: Unicode.Scalar) -> Glyph<Self>? {
    let bitmapOffset: Int

    switch scalar {
    case " ":
      return Glyph(
        bitmapOffset: 0,
        width: 0,
        height: 0,
        left: 0,
        top: 0,
        advance: 1
      )
    case "0":
      bitmapOffset = 0
    case "1":
      bitmapOffset = 15
    case "?":
      bitmapOffset = 30
    case "M":
      bitmapOffset = 45
    default:
      return nil
    }

    return Glyph(
      bitmapOffset: bitmapOffset,
      width: 3,
      height: 5,
      left: 0,
      top: -5,
      advance: glyphAdvance
    )
  }

  static func withCoverage<Result>(
    for glyph: Glyph<Self>,
    _ body: (Span<UInt8>) -> Result
  ) -> Result {
    let start = glyph.bitmapOffset
    let count = glyph.width * glyph.height

    return body(
      bitmap.span.extracting(start..<(start + count))
    )
  }
}
