//
//  Font.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-09.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

protocol Font {

  static var pixelFormat: PixelFormat { get }

  static var ascent: Int { get }
  static var descent: Int { get }
  static var lineHeight: Int { get }

  static func glyph(for scalar: Unicode.Scalar) -> Glyph<Self>?
  static func withCoverage<Result>(for glyph: Glyph<Self>, _ body: (Span<UInt8>) -> Result) -> Result
}

extension Font {

  static var pixelFormat: PixelFormat { .a8 }

  static func advance(
    of text: StaticString
  ) -> Int {
    var advance = 0

    text.withUTF8Buffer { utf8 in
      for byte in utf8 {
        guard let scalar = Unicode.Scalar(UInt32(byte)),
          let glyph = glyph(for: scalar)
        else { continue }

        advance += glyph.advance
      }
    }

    return advance
  }

  static func advance(of values: borrowing Span<UInt32>) -> Int {
    var advance = 0

    for value in values {
      guard let scalar = Unicode.Scalar(value),
        let glyph = glyph(for: scalar)
      else { continue }

      advance += glyph.advance
    }

    return advance
  }
}
