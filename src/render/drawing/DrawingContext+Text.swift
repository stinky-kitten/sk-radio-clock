//
//  DrawingContext+Text.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-08.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension DrawingContext {
  @discardableResult
  mutating func drawGlyph<F: Font>(
    _ glyph: Glyph<F>,
    atPen pen: PixelPoint,
    color: PixelColor32,
    clippedTo clipFrame: PixelRect? = nil
  ) -> PixelPoint {
    guard checkDeadline() else { return pen }

    F.withCoverage(for: glyph) { pixelValues in
      var index = 0

      for glyphY in 0..<glyph.height {
        let y = pen.y + glyph.top + glyphY

        for glyphX in 0..<glyph.width {
          let coverage = pixelValues[index]
          index += 1

          guard coverage != 0 else { continue }

          let x = pen.x + glyph.left + glyphX
          if let clipFrame {
            guard x >= clipFrame.minX,
              x < clipFrame.maxX,
              y >= clipFrame.minY,
              y < clipFrame.maxY
            else { continue }
          }

          let alpha = UInt8((UInt32(coverage) * UInt32(color.alpha) + 127) / 255)
          if alpha == 255 {
            _ = setPixel(at: PixelPoint(x: x, y: y), to: color)
          } else if alpha > 0 {
            _ = blendPixel(at: PixelPoint(x: x, y: y), to: color, withAlpha: alpha)
          }
        }
      }
    }

    return PixelPoint(x: pen.x + glyph.advance, y: pen.y)
  }
}

extension DrawingContext {
  @discardableResult
  mutating func drawString<F: Font>(
    _ text: StaticString,
    font: F.Type,
    atPen initialPen: PixelPoint,
    color: PixelColor32,
    clippedTo clipFrame: PixelRect? = nil
  ) -> PixelPoint {
    var pen = initialPen

    text.withUTF8Buffer { utf8 in
      for byte in utf8 {
        guard canContinue else { break }
        // Current embedded fonts contain ASCII glyphs only but it will return nil for any non-ASCII byte, so we can skip those.
        guard let scalar = Unicode.Scalar(UInt32(byte)),
          let glyph = F.glyph(for: scalar)
        else { continue }

        pen = drawGlyph(glyph, atPen: pen, color: color, clippedTo: clipFrame)
      }
    }

    return pen
  }
}

extension DrawingContext {
  @discardableResult
  mutating func drawASCII<F: Font>(
    _ bytes: borrowing Span<UInt8>,
    font: F.Type,
    atPen initialPen: PixelPoint,
    color: PixelColor32,
    clippedTo clipFrame: PixelRect? = nil
  ) -> PixelPoint {
    var pen = initialPen

    for byte in bytes {
      guard canContinue else { break }
      guard let scalar = Unicode.Scalar(UInt32(byte)),
        let glyph = F.glyph(for: scalar)
      else { continue }

      pen = drawGlyph(glyph, atPen: pen, color: color, clippedTo: clipFrame)
    }

    return pen
  }
}
