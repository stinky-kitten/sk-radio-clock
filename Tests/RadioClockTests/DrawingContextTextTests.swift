//
//  DrawingContextTextTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

private let textSentinel: UInt32 = 0x1234_5678

private enum TextCoverageFixtureFont: Font {
  static let ascent = 2
  static let descent = 0
  static let lineHeight = 2

  static let dot = Glyph<Self>(bitmapOffset: 0, width: 2, height: 2, left: 1, top: -2, advance: 3)
  static let faintPixel = Glyph<Self>(bitmapOffset: 4, width: 1, height: 1, left: 0, top: 0, advance: 1)
  private static let coverage: [UInt8] = [83, 35, 80, 34, 1]

  static func glyph(for scalar: Unicode.Scalar) -> Glyph<Self>? {
    scalar == "." ? dot : nil
  }

  static func withCoverage<Result>(for glyph: Glyph<Self>, _ body: (Span<UInt8>) -> Result) -> Result {
    let start = glyph.bitmapOffset
    return body(coverage.span.extracting(start..<(start + glyph.width * glyph.height)))
  }
}

@Test(
  "Text glyph placement uses the pen baseline and preserves transparent pixels",
  arguments: [
    (PixelColor32.white, UInt32(0xffff_ffff)), (.black, 0xff00_0000),
    (PixelColor32(red: UInt32(255), green: UInt32(0), blue: UInt32(0), alpha: UInt32(0)), textSentinel),
    (PixelColor32(red: UInt32(128), green: UInt32(64), blue: UInt32(32), alpha: UInt32(128)), 0xff5a_4b4c),
  ]
    as [(PixelColor32, UInt32)])
func textSingleBitGlyph(_ colour: PixelColor32, _ packed: UInt32) throws {
  let glyph = try #require(MSFBitFont.glyph(for: "0"))
  let result = drawTextFixture { context in
    context.drawGlyph(glyph, atPen: PixelPoint(x: 2, y: 6), color: colour)
  }
  #expect(result.pen == PixelPoint(x: 5, y: 6))
  let coordinates = [
    (2, 1), (3, 1), (4, 1), (2, 2), (4, 2), (2, 3), (4, 3),
    (2, 4), (4, 4), (2, 5), (3, 5), (4, 5),
  ]
  expectTextPixels(result.pixels, coordinates: coordinates.map { ($0.0, $0.1, packed) })
}

@Test("Text strings and byte spans position bit glyphs around a one-column space", arguments: [false, true])
func textBitSequence(_ ascii: Bool) {
  let bytes: [UInt8] = [48, 32, 49]
  let result = drawTextFixture { context in
    if ascii {
      return context.drawASCII(bytes.span, font: MSFBitFont.self, atPen: PixelPoint(x: 0, y: 5), color: .white)
    }
    return context.drawString("0 1", font: MSFBitFont.self, atPen: PixelPoint(x: 0, y: 5), color: .white)
  }
  #expect(result.pen == PixelPoint(x: 7, y: 5))
  let coordinates = [
    (0, 0), (1, 0), (2, 0), (5, 0),
    (0, 1), (2, 1), (4, 1), (5, 1),
    (0, 2), (2, 2), (5, 2), (0, 3), (2, 3), (5, 3),
    (0, 4), (1, 4), (2, 4), (4, 4), (5, 4), (6, 4),
  ]
  expectTextPixels(result.pixels, coordinates: coordinates.map { ($0.0, $0.1, 0xffff_ffff) })
}

@Test("Text proportional advances and positive bearings position i dot W exactly", arguments: [false, true])
func textProportionalSequence(_ ascii: Bool) {
  let bytes: [UInt8] = [105, 46, 87]
  let size = PixelSize(width: 18, height: 8)
  let result = drawTextFixture(size: size) { context in
    if ascii {
      return context.drawASCII(bytes.span, font: PixelOperator8Font.self, atPen: PixelPoint(x: 1, y: 8), color: .white)
    }
    return context.drawString("i.W", font: PixelOperator8Font.self, atPen: PixelPoint(x: 1, y: 8), color: .white)
  }
  #expect(result.pen == PixelPoint(x: 17, y: 8))
  let ink = [
    (3, 1), (10, 1), (16, 1), (10, 2), (16, 2),
    (3, 3), (10, 3), (13, 3), (16, 3), (3, 4), (10, 4), (13, 4), (16, 4),
    (3, 5), (10, 5), (13, 5), (16, 5), (3, 6), (10, 6), (13, 6), (16, 6),
    (3, 7), (7, 7), (11, 7), (12, 7), (14, 7), (15, 7),
  ]
  expectTextPixels(result.pixels, size: size, coordinates: ink.map { ($0.0, $0.1, 0xffff_ffff) })
}

// Dot coverage [83, 35, 80, 34] at tint alpha 128 gives effective alpha [42, 18, 40, 17].
// For the first pixel over black, red rounds from 128 × 42/255 to 21.
// Applying tint alpha again would give red 11, so this case catches double application.
@Test(
  "Text combines glyph coverage and tint alpha once over black and coloured backgrounds",
  arguments: [
    (
      textSentinel, [0xff4d_4f5b, 0xff3e_536c, 0xff4c_4f5c, 0xff3e_536c],
      [0xff41_526a, 0xff39_5472, 0xff40_536a, 0xff39_5572]
    ),
    (
      0xff20_4060, [0xff3f_404b, 0xff2d_4057, 0xff3e_404c, 0xff2d_4057],
      [0xff30_4055, 0xff27_405b, 0xff2f_4056, 0xff26_405c]
    ),
    (
      0xff00_0000, [0xff2a_150a, 0xff12_0904, 0xff28_140a, 0xff11_0904],
      [0xff15_0b05, 0xff09_0502, 0xff14_0a05, 0xff09_0402]
    ),
  ] as [(UInt32, [UInt32], [UInt32])], [UInt8(0), 128, 255])
func textIntermediateTint(_ sample: (UInt32, [UInt32], [UInt32]), _ alpha: UInt8) {
  let (background, opaque, translucent) = sample
  let expected = alpha == 255 ? opaque : translucent
  let glyph = TextCoverageFixtureFont.dot
  let result = drawTextFixture(background: background) { context in
    context.drawGlyph(
      glyph, atPen: PixelPoint(x: 1, y: 4),
      color: PixelColor32(red: 128, green: 64, blue: 32, alpha: alpha))
  }
  #expect(result.pen == PixelPoint(x: 4, y: 4))
  expectTextPixels(
    result.pixels, background: background,
    coordinates: alpha == 0
      ? []
      : [
        (2, 2, expected[0]), (3, 2, expected[1]),
        (2, 3, expected[2]), (3, 3, expected[3]),
      ])
}

@Test("Text descenders extend below the baseline without moving the returned pen")
func textDescender() throws {
  let glyph = try #require(PixelOperator8Font.glyph(for: "g"))
  let size = PixelSize(width: 8, height: 8)
  let result = drawTextFixture(size: size) { context in
    context.drawGlyph(glyph, atPen: PixelPoint(x: 1, y: 6), color: .white)
  }
  #expect(result.pen == PixelPoint(x: 7, y: 6))
  let ink = [
    (3, 1), (4, 1), (5, 1), (6, 1), (2, 2), (6, 2), (2, 3), (6, 3),
    (3, 4), (4, 4), (5, 4), (6, 4), (6, 5), (3, 6), (4, 6), (5, 6),
  ]
  expectTextPixels(result.pixels, size: size, coordinates: ink.map { ($0.0, $0.1, 0xffff_ffff) })
}

@Test(
  "Text glyph clipping preserves visible pixels and advances even when nothing is visible",
  arguments: [
    ("left", PixelPoint(x: -1, y: 5), [(0, 0), (1, 0), (1, 1), (1, 2), (1, 3), (0, 4), (1, 4)]),
    ("right", PixelPoint(x: 7, y: 5), [(7, 0), (7, 1), (7, 2), (7, 3), (7, 4)]),
    ("top", PixelPoint(x: 2, y: 1), [(2, 0), (3, 0), (4, 0)]),
    ("bottom", PixelPoint(x: 2, y: 11), [(2, 6), (3, 6), (4, 6), (2, 7), (4, 7)]),
    ("outside left", PixelPoint(x: -3, y: 5), []),
    ("outside right", PixelPoint(x: 8, y: 5), []),
    ("outside top", PixelPoint(x: 2, y: 0), []),
    ("outside bottom", PixelPoint(x: 2, y: 13), []),
  ] as [(String, PixelPoint, [(Int, Int)])])
func textGlyphClipping(_ name: String, _ pen: PixelPoint, _ coordinates: [(Int, Int)]) throws {
  let glyph = try #require(MSFBitFont.glyph(for: "0"))
  let result = drawTextFixture { context in
    context.drawGlyph(glyph, atPen: pen, color: .white)
  }
  #expect(result.pen == PixelPoint(x: pen.x + 3, y: pen.y))
  expectTextPixels(result.pixels, coordinates: coordinates.map { ($0.0, $0.1, 0xffff_ffff) })
}

@Test(
  "Text explicit clip frames use exclusive edges independently of framebuffer clipping",
  arguments: [
    ("interior", PixelRect(x: 3, y: 2, width: 2, height: 2), [(4, 2), (4, 3)]),
    ("zero width", PixelRect(x: 2, y: 1, width: 0, height: 5), []),
    ("zero height", PixelRect(x: 2, y: 1, width: 3, height: 0), []),
    ("outside", PixelRect(x: -10, y: -10, width: 11, height: 11), []),
  ] as [(String, PixelRect, [(Int, Int)])])
func textExplicitClip(_ name: String, _ clip: PixelRect, _ coordinates: [(Int, Int)]) throws {
  let glyph = try #require(MSFBitFont.glyph(for: "0"))
  let result = drawTextFixture { context in
    context.drawGlyph(
      glyph, atPen: PixelPoint(x: 2, y: 6),
      color: .white, clippedTo: clip)
  }
  #expect(result.pen == PixelPoint(x: 5, y: 6))
  expectTextPixels(result.pixels, coordinates: coordinates.map { ($0.0, $0.1, 0xffff_ffff) })
}

@Test("Text beyond the drawing frame clips later glyphs without changing their advances", arguments: [false, true])
func textBeyondFrame(_ ascii: Bool) {
  let size = PixelSize(width: 5, height: 5)
  let bytes: [UInt8] = [48, 48, 48]
  let result = drawTextFixture(size: size) { context in
    if ascii {
      return context.drawASCII(bytes.span, font: MSFBitFont.self, atPen: PixelPoint(x: 0, y: 5), color: .white)
    }
    return context.drawString("000", font: MSFBitFont.self, atPen: PixelPoint(x: 0, y: 5), color: .white)
  }
  #expect(result.pen == PixelPoint(x: 9, y: 5))
  let coordinates = [
    (0, 0), (1, 0), (2, 0), (3, 0), (4, 0),
    (0, 1), (2, 1), (3, 1), (0, 2), (2, 2), (3, 2),
    (0, 3), (2, 3), (3, 3), (0, 4), (1, 4), (2, 4), (3, 4), (4, 4),
  ]
  expectTextPixels(result.pixels, size: size, coordinates: coordinates.map { ($0.0, $0.1, 0xffff_ffff) })
}

@Test(
  "Text empty strings spaces and unsupported characters have distinct advances but no ink",
  arguments: [("", 0), ("   ", 3), ("Xé", 0)] as [(StaticString, Int)], [false, true])
func textEmptyAndUnsupported(_ sample: (StaticString, Int), _ ascii: Bool) {
  let (text, advance) = sample
  let bytes = text.withUTF8Buffer { Array($0) }
  let result = drawTextFixture { context in
    if ascii {
      return context.drawASCII(bytes.span, font: MSFBitFont.self, atPen: PixelPoint(x: 2, y: 6), color: .white)
    }
    return context.drawString(text, font: MSFBitFont.self, atPen: PixelPoint(x: 2, y: 6), color: .white)
  }
  #expect(result.pen == PixelPoint(x: 2 + advance, y: 6))
  expectTextPixels(result.pixels, coordinates: [])
}

@Test("Text skips unsupported controls and UTF-8 bytes without replacing or spacing glyphs", arguments: [false, true])
func textSkippedCharacters(_ ascii: Bool) {
  let bytes: [UInt8] = [0, 88, 48, 195, 169, 49, 127, 255]
  let result = drawTextFixture { context in
    if ascii {
      return context.drawASCII(bytes.span, font: MSFBitFont.self, atPen: PixelPoint(x: 0, y: 5), color: .white)
    }
    return context.drawString("\0X0é1\u{7f}", font: MSFBitFont.self, atPen: PixelPoint(x: 0, y: 5), color: .white)
  }
  #expect(result.pen == PixelPoint(x: 6, y: 5))
  let coordinates = [
    (0, 0), (1, 0), (2, 0), (4, 0), (0, 1), (2, 1), (3, 1), (4, 1),
    (0, 2), (2, 2), (4, 2), (0, 3), (2, 3), (4, 3),
    (0, 4), (1, 4), (2, 4), (3, 4), (4, 4), (5, 4),
  ]
  expectTextPixels(result.pixels, coordinates: coordinates.map { ($0.0, $0.1, 0xffff_ffff) })
}

@Test("Text direct clock-separator drawing uses its bearing and preserves the transparent gap")
func textClockSeparatorGlyph() throws {
  let glyph = try #require(ClockFont.glyph(for: "꞉"))
  let size = PixelSize(width: 12, height: 12)
  let result = drawTextFixture(size: size) { context in
    context.drawGlyph(glyph, atPen: PixelPoint(x: 2, y: 13), color: .white)
  }
  #expect(result.pen == PixelPoint(x: 9, y: 13))
  let coordinates = [
    (4, 1), (5, 1), (6, 1), (4, 2), (5, 2), (6, 2), (4, 3), (5, 3), (6, 3),
    (4, 8), (5, 8), (6, 8), (4, 9), (5, 9), (6, 9), (4, 10), (5, 10), (6, 10),
  ]
  expectTextPixels(result.pixels, size: size, coordinates: coordinates.map { ($0.0, $0.1, 0xffff_ffff) })
}

@Test(
  "Text clock-string helpers omit separators rather than rendering a fallback",
  arguments: ["0:0", "0꞉0"] as [StaticString], [false, true])
func textClockStrings(_ text: StaticString, _ ascii: Bool) {
  let bytes = text.withUTF8Buffer { Array($0) }
  let size = PixelSize(width: 26, height: 18)
  let result = drawTextFixture(size: size) { context in
    let clip = PixelRect(x: 0, y: 0, width: 26, height: 1)
    if ascii {
      return context.drawASCII(
        bytes.span, font: ClockFont.self, atPen: PixelPoint(x: 0, y: 16), color: .white, clippedTo: clip)
    }
    return context.drawString(
      text, font: ClockFont.self, atPen: PixelPoint(x: 0, y: 16), color: .white, clippedTo: clip)
  }
  #expect(result.pen == PixelPoint(x: 24, y: 16))
  expectTextPixels(
    result.pixels, size: size,
    coordinates: [
      (4, 0, 0xff4d_6b89), (5, 0, 0xff6d_869e), (6, 0, 0xff6e_869f), (7, 0, 0xff44_6383),
      (16, 0, 0xff4d_6b89), (17, 0, 0xff6d_869e), (18, 0, 0xff6e_869f), (19, 0, 0xff44_6383),
    ])
}

@Test("Text zero-area space advances the pen without touching framebuffer memory")
func textSpaceGlyph() throws {
  let glyph = try #require(PixelOperator8Font.glyph(for: " "))
  let result = drawTextFixture { context in
    context.drawGlyph(glyph, atPen: PixelPoint(x: 2, y: 6), color: .white)
  }
  #expect(result.pen == PixelPoint(x: 5, y: 6))
  expectTextPixels(result.pixels, coordinates: [])
}

@Test("Text at the 64 by 64 panel corner preserves canaries and the final visible glyph row")
func textPanelCorner() throws {
  let glyph = try #require(MSFBitFont.glyph(for: "0"))
  let size = PixelSize(width: 64, height: 64)
  let result = drawTextFixture(size: size) { context in
    context.drawGlyph(glyph, atPen: PixelPoint(x: 61, y: 64), color: .white)
  }
  #expect(result.pen == PixelPoint(x: 64, y: 64))
  let coordinates = [
    (61, 59), (62, 59), (63, 59), (61, 60), (63, 60), (61, 61), (63, 61),
    (61, 62), (63, 62), (61, 63), (62, 63), (63, 63),
  ]
  expectTextPixels(result.pixels, size: size, coordinates: coordinates.map { ($0.0, $0.1, 0xffff_ffff) })
}

@Test(
  "Text partially clipped A8 coverage composites over non-black background with independent bounds",
  arguments: [
    (
      "left", PixelPoint(x: -2, y: 4), Optional<PixelRect>.none,
      [(0, 2, UInt32(0xff2d_4057)), (0, 3, 0xff2d_4057)]
    ),
    (
      "right", PixelPoint(x: 6, y: 4), nil,
      [(7, 2, 0xff3f_404b), (7, 3, 0xff3e_404c)]
    ),
    (
      "top", PixelPoint(x: 1, y: 1), nil,
      [(2, 0, 0xff3e_404c), (3, 0, 0xff2d_4057)]
    ),
    (
      "bottom", PixelPoint(x: 1, y: 9), nil,
      [(2, 7, 0xff3f_404b), (3, 7, 0xff2d_4057)]
    ),
    (
      "explicit clip", PixelPoint(x: 1, y: 4), PixelRect(x: 3, y: 3, width: 1, height: 1),
      [(3, 3, 0xff2d_4057)]
    ),
    ("outside", PixelPoint(x: 8, y: 4), nil, []),
  ] as [(String, PixelPoint, PixelRect?, [(Int, Int, UInt32)])])
func textClippedCoverageBlend(
  _ name: String, _ pen: PixelPoint, _ clip: PixelRect?,
  _ expected: [(Int, Int, UInt32)]
) {
  let glyph = TextCoverageFixtureFont.dot
  let result = drawTextFixture(background: 0xff20_4060) { context in
    context.drawGlyph(
      glyph, atPen: pen,
      color: PixelColor32(red: UInt32(128), green: UInt32(64), blue: UInt32(32)),
      clippedTo: clip)
  }
  #expect(result.pen == PixelPoint(x: pen.x + 3, y: pen.y))
  expectTextPixels(result.pixels, background: 0xff20_4060, coordinates: expected)
}

@Test(
  "Text rounds combined alpha on either side of half before blending RGB",
  arguments: [(UInt8(127), UInt32(0xff00_0000)), (128, 0xff01_0000), (255, 0xff01_0000)])
func textCoverageRounding(_ alpha: UInt8, _ expected: UInt32) {
  // Coverage 1 rounds to zero at alpha 127 and to one at alpha 128.
  // With effective alpha one, red 128 contributes 128/255, which also rounds to one.
  let result = drawTextFixture(background: 0xff00_0000) { context in
    context.drawGlyph(
      TextCoverageFixtureFont.faintPixel, atPen: PixelPoint(x: 0, y: 0),
      color: PixelColor32(red: 128, green: 0, blue: 0, alpha: alpha))
  }
  #expect(result.pen == PixelPoint(x: 1, y: 0))
  expectTextPixels(result.pixels, background: 0xff00_0000, coordinates: [(0, 0, expected)])
}

@Test("Text overlapping partial glyphs blend over the previous glyph result")
func textRepeatedCoverageBlend() {
  let glyph = TextCoverageFixtureFont.dot
  let result = drawTextFixture(background: 0xff20_4060) { context in
    let colour = PixelColor32(red: UInt32(128), green: UInt32(64), blue: UInt32(32))
    context.drawGlyph(glyph, atPen: PixelPoint(x: 1, y: 4), color: colour)
    return context.drawGlyph(glyph, atPen: PixelPoint(x: 1, y: 4), color: colour)
  }
  #expect(result.pen == PixelPoint(x: 4, y: 4))
  expectTextPixels(
    result.pixels, background: 0xff20_4060,
    coordinates: [
      (2, 2, 0xff54_403d), (3, 2, 0xff38_404f),
      (2, 3, 0xff53_403e), (3, 3, 0xff38_4050),
    ])
}

private func drawTextFixture(
  size: PixelSize = PixelSize(width: 8, height: 8),
  background: UInt32 = textSentinel,
  _ draw: (inout DrawingContext) -> PixelPoint
) -> (pixels: [UInt32], pen: PixelPoint) {
  let count = size.width * size.height
  let prefix: [UInt32] = [0xdead_beef, 0xcafe_babe, 0x1122_3344, 0x5566_7788]
  let suffix: [UInt32] = [0x99aa_bbcc, 0xddee_ff00, 0xface_feed, 0xbaad_f00d]
  var storage = prefix + Array(repeating: background, count: count) + suffix
  let pen = storage.withUnsafeMutableBufferPointer { buffer in
    var context = DrawingContext(
      framebuffer: UnsafeMutableBufferPointer(
        start: buffer.baseAddress!.advanced(by: 4), count: count), contextSize: size, pixelFormat: .bgrx8888)!
    return draw(&context)
  }
  #expect(Array(storage.prefix(4)) == prefix && Array(storage.suffix(4)) == suffix)
  return (Array(storage[4..<(count + 4)]), pen)
}

// Compare against fixed pixel coordinates and literal colours, never against a
// second rasterizer or colours obtained by rendering another reference image.
private func expectTextPixels(
  _ pixels: [UInt32], size: PixelSize = PixelSize(width: 8, height: 8),
  background: UInt32 = textSentinel, coordinates: [(Int, Int, UInt32)]
) {
  for y in 0..<size.height {
    for x in 0..<size.width {
      let expected = coordinates.first { $0.0 == x && $0.1 == y }?.2 ?? background
      #expect(pixels[y * size.width + x] == expected)
    }
  }
}

@Test("A glyph completes its raster once started and leaves the next glyph untouched at expiry")
func textGlyphDeadlineBoundary() throws {
  let glyph = try #require(MSFBitFont.glyph(for: "0"))
  let expected = drawTextFixture { context in
    context.drawGlyph(glyph, atPen: PixelPoint(x: 2, y: 6), color: .white)
  }
  var pixels = Array(repeating: textSentinel, count: 64)
  try pixels.withUnsafeMutableBufferPointer { buffer in
    var context = try #require(
      DrawingContext(
        framebuffer: buffer, contextSize: PixelSize(width: 8, height: 8),
        pixelFormat: .bgrx8888,
        renderDeadline: RenderDeadline(timeUs: 100)))
    RenderHostTime.withTimestamps([99, 100]) {
      let pen = context.drawGlyph(glyph, atPen: PixelPoint(x: 2, y: 6), color: .white)
      #expect(pen == expected.pen && context.status == .active)
      #expect(RenderHostTime.readCount == 1)
      let rejectedPen = context.drawGlyph(glyph, atPen: pen, color: .white)
      #expect(rejectedPen == pen && context.status == .deadlineExceeded)
      #expect(RenderHostTime.readCount == 2)
    }
  }
  #expect(pixels == expected.pixels)
}

@Test(
  "A1 text blends full coverage with source alpha and preserves zero coverage and clipped pixels",
  arguments: [
    (nil, [1, 2, 3, 4, 5, 7]),
    (PixelRect(x: 3, y: 2, width: 1, height: 5), [2, 3, 4, 5]),
  ] as [(PixelRect?, [Int])])
func textA1CoverageBlend(_ clip: PixelRect?, _ inkRows: [Int]) throws {
  let glyph = try #require(PixelOperator8Font.glyph(for: "!"))
  let result = drawTextFixture(background: 0xff20_4060) { context in
    context.drawGlyph(
      glyph, atPen: PixelPoint(x: 1, y: 8),
      color: PixelColor32(red: UInt32(128), green: 64, blue: 32, alpha: 128),
      clippedTo: clip)
  }
  #expect(result.pen == PixelPoint(x: 5, y: 8))
  expectTextPixels(
    result.pixels, background: 0xff20_4060,
    coordinates: inkRows.map { (3, $0, 0xff50_4040) })
}
