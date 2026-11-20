//
//  FontTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

@Test("Test font pixelFormats")
func fontPixelFormats() {
  #expect(MSFBitFont.pixelFormat == .a8)
  #expect(ClockFont.pixelFormat == .a8)
}

@Test("Font metrics describe the current bit and clock assets")
func fontMetrics() {
  #expect(MSFBitFont.ascent == 5 && MSFBitFont.descent == 0 && MSFBitFont.lineHeight == 5)
  #expect(ClockFont.ascent == 20 && ClockFont.descent == 5 && ClockFont.lineHeight == 25)
}

@Test("Font lookup accepts each font's exact ASCII repertoire without fallback", arguments: UInt32(0)...127)
func fontASCIIRepertoire(_ value: UInt32) throws {
  let scalar = try #require(Unicode.Scalar(value))
  #expect((MSFBitFont.glyph(for: scalar) != nil) == [32, 48, 49, 63, 77].contains(value))
  #expect((ClockFont.glyph(for: scalar) != nil) == ((48...57).contains(value) || value == 63))
}

@Test(
  "Font non-ASCII lookup supports only the clock's modifier-letter colon",
  arguments: [UInt32(128), 255, 256, 0x03a9, 0x2026, 0xa789, 0x1f600, 0x10ffff])
func fontUnicodeLookup(_ value: UInt32) throws {
  let scalar = try #require(Unicode.Scalar(value))
  #expect(MSFBitFont.glyph(for: scalar) == nil)
  #expect((ClockFont.glyph(for: scalar) != nil) == (value == 0xa789))
}

@Test(
  "Bit font glyphs have fixed three-column ink and a one-column space",
  arguments: [
    (UInt32(32), 0, 0, 0, 0, 1), (48, 3, 5, 0, -5, 3),
    (49, 3, 5, 0, -5, 3), (63, 3, 5, 0, -5, 3), (77, 3, 5, 0, -5, 3),
  ]
    as [(UInt32, Int, Int, Int, Int, Int)])
func fontBitGlyphMetrics(_ scalar: UInt32, _ width: Int, _ height: Int, _ left: Int, _ top: Int, _ advance: Int) throws
{
  let character = try #require(Unicode.Scalar(scalar))
  try expectFontMetrics(
    MSFBitFont.glyph(for: character),
    width: width, height: height, left: left, top: top, advance: advance)
}

@Test(
  "Clock font digits use twelve-column advances while question and colon have their own metrics",
  arguments: [
    (UInt32(48), 12, 17, 0, -16, 12), (49, 11, 16, 1, -16, 12),
    (50, 12, 16, 0, -16, 12), (51, 12, 17, 0, -16, 12),
    (52, 13, 16, 0, -16, 12), (53, 12, 17, 0, -16, 12),
    (54, 12, 17, 0, -16, 12), (55, 12, 16, 0, -16, 12),
    (56, 12, 17, 0, -16, 12), (57, 12, 17, 0, -16, 12),
    (63, 12, 16, 1, -16, 13), (0xa789, 3, 10, 2, -12, 7),
  ] as [(UInt32, Int, Int, Int, Int, Int)])
func fontClockGlyphMetrics(
  _ scalar: UInt32, _ width: Int, _ height: Int, _ left: Int, _ top: Int, _ advance: Int
) throws {
  let character = try #require(Unicode.Scalar(scalar))
  try expectFontMetrics(
    ClockFont.glyph(for: character),
    width: width, height: height, left: left, top: top, advance: advance)
}

@Test(
  "Bit font masks match explicit zero one question and marker reference patterns",
  arguments: [
    (UInt32(48), ["111", "101", "101", "101", "111"]),
    (49, ["010", "110", "010", "010", "111"]),
    (63, ["111", "001", "011", "000", "010"]),
    (77, ["101", "111", "111", "101", "101"]),
  ] as [(UInt32, [String])])
func fontBitReferenceMasks(_ value: UInt32, _ rows: [String]) throws {
  let character = try #require(Unicode.Scalar(value))
  let glyph = try #require(MSFBitFont.glyph(for: character))
  let expected = rows.flatMap { Array($0.utf8) }

  #expect(expected.count == 15)

  MSFBitFont.withCoverage(for: glyph) { coverage in
    #expect(coverage.count == expected.count)

    for index in expected.indices {
      #expect(coverage[index] == (expected[index] == 49 ? 255 : 0))
    }
  }
}

@Test("Clock separator mask contains two opaque three-by-three blocks with four blank rows")
func fontClockSeparatorMask() throws {
  let glyph = try #require(ClockFont.glyph(for: "꞉"))
  let expected: [UInt8] = [
    255, 255, 255, 255, 255, 255, 255, 255, 255,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    255, 255, 255, 255, 255, 255, 255, 255, 255,
  ]
  #expect(glyph.width * glyph.height == 30)
  for index in expected.indices {
    ClockFont.withCoverage(for: glyph) { coverage in
      #expect(coverage[index] == expected[index])
    }
  }
}

@Test("Clock question mark has opaque ink and intermediate coverage without an invented fallback")
func fontClockQuestionCoverage() throws {
  let glyph = try #require(ClockFont.glyph(for: "?"))
  let count = glyph.width * glyph.height

  ClockFont.withCoverage(for: glyph) { coverage in
    #expect(coverage.count == count)

    var hasOpaque = false
    var hasPartial = false

    for alpha in coverage {
      if alpha == 255 { hasOpaque = true }
      if alpha > 0 && alpha < 255 { hasPartial = true }
    }

    #expect(hasOpaque)
    #expect(hasPartial)
  }
}

@Test("Clock font visible glyph extents differ from the reserved ascent and descent metrics")
func fontVisibleInkBounds() throws {
  var clockTop = 0
  var clockBottom = 0
  for value: UInt32 in [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 63, 0xa789] {
    let scalar = try #require(Unicode.Scalar(value))
    let glyph = try #require(ClockFont.glyph(for: scalar))
    clockTop = min(clockTop, glyph.top)
    clockBottom = max(clockBottom, glyph.top + glyph.height)
  }
  #expect(clockTop == -16 && clockBottom == 1)
}

@Test(
  "Bit text measurements include narrow spaces and skip unsupported characters",
  arguments: [
    ("", 0), (" ", 1), ("0", 3), ("0 1", 7), ("M M", 7),
    ("? ?", 7), ("0101", 12), ("X0é1", 6),
  ] as [(StaticString, Int)])
func fontBitMeasurement(_ text: StaticString, _ expected: Int) {
  let bytes = text.withUTF8Buffer { $0.map(UInt32.init) }
  #expect(MSFBitFont.advance(of: text) == expected)
  #expect(MSFBitFont.advance(of: bytes.span) == expected)
}

@Test(
  "Clock ASCII measurements omit both ASCII colon and the Unicode separator",
  arguments: [
    ("", 0), ("0", 12), ("09", 24), ("??", 26), ("12:34", 48),
    ("12꞉34", 48), ("?0?", 38), ("0123456789", 120), (" 1A", 12),
  ] as [(StaticString, Int)])
func fontClockMeasurement(_ text: StaticString, _ expected: Int) {
  let bytes = text.withUTF8Buffer { $0.map(UInt32.init) }
  #expect(ClockFont.advance(of: text) == expected)
  #expect(ClockFont.advance(of: bytes.span) == expected)
}

@Test("Font byte measurements skip unsupported ASCII controls and high bytes")
func fontUnsupportedByteMeasurement() {
  let bytes: [UInt32] = [255, 49, 128, 58, 50, 0, 10]
  #expect(ClockFont.advance(of: bytes.span) == 24)
  #expect(MSFBitFont.advance(of: bytes.span) == 3)
}

private func expectFontMetrics<Font>(
  _ optional: Glyph<Font>?, width: Int, height: Int,
  left: Int, top: Int, advance: Int
) throws {
  let glyph = try #require(optional)
  #expect(glyph.width == width && glyph.height == height)
  #expect(glyph.left == left && glyph.top == top)
  #expect(glyph.advance == advance)
}

@Test("Scalar-span font measurement includes the clock separator and skips invalid scalar values")
func fontUnicodeScalarMeasurement() {
  let values: [UInt32] = [49, 0xa789, 50, 0x110000]
  #expect(ClockFont.advance(of: values.span) == 31)
}

@Test("Pixel Operator 8 packs printable ASCII without row padding")
func fontPixelOperator8Storage() throws {
  #expect(PixelOperator8Font.pixelFormat == .a1)
  #expect(PixelOperator8Font.ascent == 7)
  #expect(PixelOperator8Font.descent == 1)
  #expect(PixelOperator8Font.lineHeight == 9)
  #expect(PixelOperator8Font.glyph(for: "é") == nil)
  #expect(PixelOperator8Font.advance(of: "iMW ") == 23)

  #expect(PixelOperator8Font.advance(of: "Wednesday") == 56)
  #expect(PixelOperator8Font.advance(of: "02.09.2026") == 56)
  #expect(PixelOperator8Font.advance(of: "0123456789") == 60)

  var offset = 0
  var maxPixels = 0
  for value in UInt32(32)...126 {
    let scalar = try #require(Unicode.Scalar(value))
    let glyph = try #require(PixelOperator8Font.glyph(for: scalar))
    let count = glyph.width * glyph.height
    #expect(glyph.bitmapOffset == offset)
    #expect(glyph.advance > 0)
    if (48...57).contains(value) { #expect(glyph.advance == 6) }
    #expect((count == 0) == (value == 32))
    PixelOperator8Font.withCoverage(for: glyph) { coverage in
      #expect(coverage.count == count)
      var hasInk = false
      for pixel in coverage {
        #expect(pixel == 0 || pixel == 255)
        hasInk = hasInk || pixel == 255
      }
      #expect(hasInk == (count > 0))
    }
    offset += (count + 7) / 8
    maxPixels = max(maxPixels, count)
  }
  #expect(offset == 374)
  #expect(maxPixels == 56 && maxPixels == PixelOperator8Font.maxGlyphPixelCount)
}

@Test(
  "Native Pixel Operator 8 masks retain bearings and cross byte boundaries",
  arguments: [
    (" ", 0, 0, 3, []),
    ("!", 2, -7, 4, ["#", "#", "#", "#", "#", ".", "#"]),
    ("\"", 2, -7, 6, ["#.#", "#.#", "#.#"]),
    ("A", 1, -7, 6, [".###.", "#...#", "#...#", "#...#", "#####", "#...#", "#...#"]),
  ] as [(Unicode.Scalar, Int, Int, Int, [String])])
func fontPixelOperator8ReferenceMasks(
  _ scalar: Unicode.Scalar, _ left: Int, _ top: Int, _ advance: Int, _ rows: [String]
) throws {
  let glyph = try #require(PixelOperator8Font.glyph(for: scalar))
  #expect(glyph.left == left && glyph.top == top && glyph.advance == advance)
  #expect(glyph.width == (rows.first?.count ?? 0))
  #expect(glyph.height == rows.count)
  let expected: [UInt8] = rows.joined().map { $0 == "#" ? 255 : 0 }
  PixelOperator8Font.withCoverage(for: glyph) { coverage in
    #expect(coverage.count == expected.count)
    for index in expected.indices { #expect(coverage[index] == expected[index]) }
  }
}
