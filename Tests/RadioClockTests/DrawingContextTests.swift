//
//  DrawingContextTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

private let drawingSentinel: UInt32 = 0x1234_5678
private let drawingColour = PixelColor32(
  red: UInt32(0x12), green: UInt32(0x34), blue: UInt32(0x56), alpha: UInt32(0xff))
private let drawingPixel: UInt32 = 0xff12_3456

@Test(
  "Drawing pixels use row-major addresses including row edges and the bottom-right corner",
  arguments: [
    (PixelPoint(x: 0, y: 0), 0), (PixelPoint(x: 7, y: 0), 7),
    (PixelPoint(x: 0, y: 1), 8), (PixelPoint(x: 7, y: 1), 15),
    (PixelPoint(x: 4, y: 2), 20), (PixelPoint(x: 0, y: 5), 40),
    (PixelPoint(x: 7, y: 5), 47),
  ])
func drawingPixelAddress(_ point: PixelPoint, _ expectedIndex: Int) {
  let pixels = drawInGuardedBuffer(size: PixelSize(width: 8, height: 6)) { context in
    #expect(context.setPixel(at: point, to: drawingColour))
  }
  for index in pixels.indices {
    #expect(pixels[index] == (index == expectedIndex ? drawingPixel : drawingSentinel))
  }
}

@Test(
  "Drawing pixels outside the context are ignored before calculating a buffer address",
  arguments: [
    PixelPoint(x: -1, y: 0), PixelPoint(x: 0, y: -1),
    PixelPoint(x: 8, y: 0), PixelPoint(x: 0, y: 6), PixelPoint(x: 8, y: 6),
    PixelPoint(x: -1, y: 5), PixelPoint(x: 8, y: 5),
    PixelPoint(x: 7, y: -1), PixelPoint(x: 7, y: 6),
    PixelPoint(x: Int.min, y: 0), PixelPoint(x: Int.max, y: 5),
    PixelPoint(x: 0, y: Int.min), PixelPoint(x: 7, y: Int.max),
  ])
func drawingPixelClipping(_ point: PixelPoint) {
  let pixels = drawInGuardedBuffer(size: PixelSize(width: 8, height: 6)) { context in
    #expect(context.setPixel(at: point, to: drawingColour))
  }
  #expect(pixels.allSatisfy { $0 == drawingSentinel })
}

@Test("Drawing context defaults fill white and stroke opaque black independently")
func drawingDefaultColours() {
  let pixels = drawInGuardedBuffer(size: PixelSize(width: 3, height: 1)) { context in
    #expect(context.contextFrame == PixelRect(x: 0, y: 0, width: 3, height: 1))
    let completed = context.fillRect(PixelRect(x: 0, y: 0, width: 1, height: 1))
    #expect(completed)
    let strokeCompleted = context.strokeLine(from: PixelPoint(x: 1, y: 0), to: PixelPoint(x: 1, y: 0))
    #expect(strokeCompleted)
  }
  #expect(pixels == [0xffff_ffff, 0xff00_0000, drawingSentinel])
}

@Test("Drawing rectangles fill exactly width by height with exclusive upper bounds")
func drawingRectangleDimensions() {
  let size = PixelSize(width: 8, height: 6)
  let pixels = drawInGuardedBuffer(size: size) { context in
    context.fillColor = drawingColour
    let completed = context.fillRect(PixelRect(x: 2, y: 1, width: 2, height: 3))
    #expect(completed)
  }
  expectDrawingPixels(
    pixels, size: size,
    coordinates: [(2, 1), (3, 1), (2, 2), (3, 2), (2, 3), (3, 3)])
}

@Test(
  "Drawing single-pixel rectangles preserve neighbours at every context corner",
  arguments: [
    PixelPoint(x: 0, y: 0), PixelPoint(x: 7, y: 0),
    PixelPoint(x: 0, y: 5), PixelPoint(x: 7, y: 5),
  ])
func drawingSinglePixelRectangle(_ point: PixelPoint) {
  let size = PixelSize(width: 8, height: 6)
  let pixels = drawInGuardedBuffer(size: size) { context in
    context.fillColor = drawingColour
    let completed = context.fillRect(PixelRect(x: point.x, y: point.y, width: 1, height: 1))
    #expect(completed)
  }
  expectDrawingPixels(pixels, size: size, coordinates: [(point.x, point.y)])
}

@Test(
  "Drawing rectangles clip independently at each edge and corner",
  arguments: [
    ("left", PixelRect(x: -2, y: 1, width: 4, height: 2), [(0, 1), (1, 1), (0, 2), (1, 2)]),
    ("right", PixelRect(x: 6, y: 1, width: 4, height: 2), [(6, 1), (7, 1), (6, 2), (7, 2)]),
    ("top", PixelRect(x: 2, y: -2, width: 2, height: 4), [(2, 0), (3, 0), (2, 1), (3, 1)]),
    ("bottom", PixelRect(x: 2, y: 4, width: 2, height: 4), [(2, 4), (3, 4), (2, 5), (3, 5)]),
    (
      "top left", PixelRect(x: -1, y: -1, width: 3, height: 3),
      [(0, 0), (1, 0), (0, 1), (1, 1)]
    ),
    ("bottom right", PixelRect(x: 7, y: 5, width: 3, height: 3), [(7, 5)]),
  ] as [(String, PixelRect, [(Int, Int)])])
func drawingRectangleClipping(_ name: String, _ rect: PixelRect, _ coordinates: [(Int, Int)]) {
  let size = PixelSize(width: 8, height: 6)
  let pixels = drawInGuardedBuffer(size: size) { context in
    context.fillColor = drawingColour
    let completed = context.fillRect(rect)
    #expect(completed)
  }
  expectDrawingPixels(pixels, size: size, coordinates: coordinates)
}

@Test(
  "Drawing clips out empty and nonoverlapping rectangles before checking the deadline",
  arguments: [
    PixelRect.zero, PixelRect(x: 2, y: 2, width: 0, height: 3),
    PixelRect(x: 2, y: 2, width: 3, height: 0),
    PixelRect(x: -2, y: 1, width: 2, height: 2),
    PixelRect(x: 8, y: 1, width: 2, height: 2),
    PixelRect(x: 2, y: -2, width: 2, height: 2),
    PixelRect(x: 2, y: 6, width: 2, height: 2),
    PixelRect(x: -3, y: -3, width: 1, height: 1),
    PixelRect(x: 9, y: 7, width: 3, height: 3),
  ])
func drawingRectangleNoIntersection(_ rect: PixelRect) {
  let pixels = drawInGuardedBuffer(
    size: PixelSize(width: 8, height: 6), renderDeadline: RenderDeadline(timeUs: 100)
  ) { context in
    context.fillColor = drawingColour
    RenderHostTime.withTimestamps([100]) {
      let completed = context.fillRect(rect)
      #expect(completed)
      #expect(context.canContinue && RenderHostTime.readCount == 0)
    }
  }
  #expect(pixels.allSatisfy { $0 == drawingSentinel })
}

@Test(
  "Drawing whole-panel fills cover all 4096 pixels while preserving surrounding canaries",
  arguments: [
    PixelRect(x: 0, y: 0, width: 64, height: 64),
    PixelRect(x: -2, y: -3, width: 68, height: 70),
  ])
func drawingWholePanelFill(_ rect: PixelRect) {
  let pixels = drawInGuardedBuffer(size: PixelSize(width: 64, height: 64)) { context in
    context.fillColor = drawingColour
    let completed = context.fillRect(rect)
    #expect(completed)
  }
  #expect(pixels.count == 4096)
  #expect(pixels.allSatisfy { $0 == drawingPixel })
}

@Test("Drawing clipped panel-corner rectangles address the final two rows correctly")
func drawingPanelCornerRectangle() {
  let pixels = drawInGuardedBuffer(size: PixelSize(width: 64, height: 64)) { context in
    context.fillColor = drawingColour
    let completed = context.fillRect(PixelRect(x: 62, y: 62, width: 4, height: 4))
    #expect(completed)
  }
  let expectedIndices = [4030, 4031, 4094, 4095]
  for index in pixels.indices {
    #expect(pixels[index] == (expectedIndices.contains(index) ? drawingPixel : drawingSentinel))
  }
}

@Test(
  "Drawing lines include single-point endpoints at interior and boundary positions",
  arguments: [PixelPoint(x: 0, y: 0), PixelPoint(x: 3, y: 4), PixelPoint(x: 7, y: 7)])
func drawingSinglePointLine(_ point: PixelPoint) {
  let size = PixelSize(width: 8, height: 8)
  let pixels = drawInGuardedBuffer(size: size) { context in
    context.strokeColor = drawingColour
    let strokeCompleted = context.strokeLine(from: point, to: point)
    #expect(strokeCompleted)
  }
  expectDrawingPixels(pixels, size: size, coordinates: [(point.x, point.y)])
}

// Explicit raster coordinates: no production line or clipping helper is used
// to construct these expectations. These slopes have no half-pixel ties.
@Test(
  "Drawing horizontal vertical diagonal and sloping lines preserve every off-line pixel",
  arguments: [
    (
      "horizontal", PixelPoint(x: 1, y: 3), PixelPoint(x: 6, y: 3),
      [(1, 3), (2, 3), (3, 3), (4, 3), (5, 3), (6, 3)]
    ),
    (
      "vertical", PixelPoint(x: 4, y: 1), PixelPoint(x: 4, y: 6),
      [(4, 1), (4, 2), (4, 3), (4, 4), (4, 5), (4, 6)]
    ),
    (
      "positive diagonal", PixelPoint(x: 1, y: 1), PixelPoint(x: 5, y: 5),
      [(1, 1), (2, 2), (3, 3), (4, 4), (5, 5)]
    ),
    (
      "negative diagonal", PixelPoint(x: 1, y: 5), PixelPoint(x: 5, y: 1),
      [(1, 5), (2, 4), (3, 3), (4, 2), (5, 1)]
    ),
    (
      "positive shallow", PixelPoint(x: 0, y: 0), PixelPoint(x: 6, y: 2),
      [(0, 0), (1, 0), (2, 1), (3, 1), (4, 1), (5, 2), (6, 2)]
    ),
    (
      "negative shallow", PixelPoint(x: 0, y: 2), PixelPoint(x: 6, y: 0),
      [(0, 2), (1, 2), (2, 1), (3, 1), (4, 1), (5, 0), (6, 0)]
    ),
    (
      "positive steep", PixelPoint(x: 0, y: 0), PixelPoint(x: 2, y: 6),
      [(0, 0), (0, 1), (1, 2), (1, 3), (1, 4), (2, 5), (2, 6)]
    ),
    (
      "negative steep", PixelPoint(x: 0, y: 6), PixelPoint(x: 2, y: 0),
      [(0, 6), (0, 5), (1, 4), (1, 3), (1, 2), (2, 1), (2, 0)]
    ),
  ] as [(String, PixelPoint, PixelPoint, [(Int, Int)])], [false, true])
func drawingLineRaster(_ sample: (String, PixelPoint, PixelPoint, [(Int, Int)]), _ reverse: Bool) {
  let (_, start, end, coordinates) = sample
  let size = PixelSize(width: 8, height: 8)
  let pixels = drawInGuardedBuffer(size: size) { context in
    context.strokeColor = drawingColour
    let strokeCompleted = context.strokeLine(from: reverse ? end : start, to: reverse ? start : end)
    #expect(strokeCompleted)
  }
  expectDrawingPixels(pixels, size: size, coordinates: coordinates)
}

@Test(
  "Drawing half-pixel line ties follow the current direction-dependent raster choices",
  arguments: [
    (
      "forward positive", PixelPoint(x: 0, y: 0), PixelPoint(x: 4, y: 2),
      [(0, 0), (1, 1), (2, 1), (3, 2), (4, 2)]
    ),
    (
      "reverse positive", PixelPoint(x: 4, y: 2), PixelPoint(x: 0, y: 0),
      [(4, 2), (3, 1), (2, 1), (1, 0), (0, 0)]
    ),
    (
      "forward negative", PixelPoint(x: 0, y: 2), PixelPoint(x: 4, y: 0),
      [(0, 2), (1, 1), (2, 1), (3, 0), (4, 0)]
    ),
    (
      "reverse negative", PixelPoint(x: 4, y: 0), PixelPoint(x: 0, y: 2),
      [(4, 0), (3, 1), (2, 1), (1, 2), (0, 2)]
    ),
  ] as [(String, PixelPoint, PixelPoint, [(Int, Int)])])
func drawingLineHalfPixelTies(
  _ name: String, _ start: PixelPoint, _ end: PixelPoint,
  _ coordinates: [(Int, Int)]
) {
  let size = PixelSize(width: 8, height: 8)
  let pixels = drawInGuardedBuffer(size: size) { context in
    context.strokeColor = drawingColour
    let strokeCompleted = context.strokeLine(from: start, to: end)
    #expect(strokeCompleted)
  }
  expectDrawingPixels(pixels, size: size, coordinates: coordinates)
}

@Test(
  "Drawing lines on all four context edges include both boundary endpoints",
  arguments: [
    (
      "top", PixelPoint(x: 0, y: 0), PixelPoint(x: 7, y: 0),
      [(0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (5, 0), (6, 0), (7, 0)]
    ),
    (
      "bottom", PixelPoint(x: 0, y: 7), PixelPoint(x: 7, y: 7),
      [(0, 7), (1, 7), (2, 7), (3, 7), (4, 7), (5, 7), (6, 7), (7, 7)]
    ),
    (
      "left", PixelPoint(x: 0, y: 0), PixelPoint(x: 0, y: 7),
      [(0, 0), (0, 1), (0, 2), (0, 3), (0, 4), (0, 5), (0, 6), (0, 7)]
    ),
    (
      "right", PixelPoint(x: 7, y: 0), PixelPoint(x: 7, y: 7),
      [(7, 0), (7, 1), (7, 2), (7, 3), (7, 4), (7, 5), (7, 6), (7, 7)]
    ),
  ] as [(String, PixelPoint, PixelPoint, [(Int, Int)])], [false, true])
func drawingLineBoundaries(
  _ sample: (String, PixelPoint, PixelPoint, [(Int, Int)]), _ reverse: Bool
) {
  let (_, start, end, coordinates) = sample
  let size = PixelSize(width: 8, height: 8)
  let pixels = drawInGuardedBuffer(size: size) { context in
    context.strokeColor = drawingColour
    let strokeCompleted = context.strokeLine(from: reverse ? end : start, to: reverse ? start : end)
    #expect(strokeCompleted)
  }
  expectDrawingPixels(pixels, size: size, coordinates: coordinates)
}

@Test(
  "Drawing lines ignore out-of-context raster pixels while retaining the visible segment",
  arguments: [
    (
      "horizontal", PixelPoint(x: -3, y: 2), PixelPoint(x: 10, y: 2),
      [(0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (5, 2), (6, 2), (7, 2)]
    ),
    (
      "vertical", PixelPoint(x: 3, y: -3), PixelPoint(x: 3, y: 10),
      [(3, 0), (3, 1), (3, 2), (3, 3), (3, 4), (3, 5), (3, 6), (3, 7)]
    ),
    (
      "positive diagonal", PixelPoint(x: -2, y: -2), PixelPoint(x: 9, y: 9),
      [(0, 0), (1, 1), (2, 2), (3, 3), (4, 4), (5, 5), (6, 6), (7, 7)]
    ),
    (
      "negative diagonal", PixelPoint(x: -2, y: 9), PixelPoint(x: 9, y: -2),
      [(0, 7), (1, 6), (2, 5), (3, 4), (4, 3), (5, 2), (6, 1), (7, 0)]
    ),
    (
      "shallow crossing", PixelPoint(x: -3, y: -1), PixelPoint(x: 9, y: 3),
      [(0, 0), (1, 0), (2, 1), (3, 1), (4, 1), (5, 2), (6, 2), (7, 2)]
    ),
  ] as [(String, PixelPoint, PixelPoint, [(Int, Int)])], [false, true])
func drawingLineClipping(_ sample: (String, PixelPoint, PixelPoint, [(Int, Int)]), _ reverse: Bool) {
  let (_, start, end, coordinates) = sample
  let size = PixelSize(width: 8, height: 8)
  let pixels = drawInGuardedBuffer(size: size) { context in
    context.strokeColor = drawingColour
    let strokeCompleted = context.strokeLine(from: reverse ? end : start, to: reverse ? start : end)
    #expect(strokeCompleted)
  }
  expectDrawingPixels(pixels, size: size, coordinates: coordinates)
}

@Test(
  "Drawing completely outside lines and points leave all pixels untouched",
  arguments: [
    (PixelPoint(x: -3, y: -1), PixelPoint(x: 10, y: -1)),
    (PixelPoint(x: -3, y: 8), PixelPoint(x: 10, y: 8)),
    (PixelPoint(x: -1, y: -3), PixelPoint(x: -1, y: 10)),
    (PixelPoint(x: 8, y: -3), PixelPoint(x: 8, y: 10)),
    (PixelPoint(x: -3, y: -3), PixelPoint(x: -1, y: -1)),
    (PixelPoint(x: 8, y: 7), PixelPoint(x: 8, y: 7)),
  ])
func drawingOutsideLine(_ start: PixelPoint, _ end: PixelPoint) {
  let pixels = drawInGuardedBuffer(size: PixelSize(width: 8, height: 8)) { context in
    context.strokeColor = drawingColour
    let strokeCompleted = context.strokeLine(from: start, to: end)
    #expect(strokeCompleted)
  }
  #expect(pixels.allSatisfy { $0 == drawingSentinel })
}

@Test(
  "Drawing lines across a 64 by 64 panel preserve all pixels outside the boundary or diagonal",
  arguments: ["bottom", "right", "diagonal"])
func drawingPanelLines(_ direction: String) {
  let pixels = drawInGuardedBuffer(size: PixelSize(width: 64, height: 64)) { context in
    context.strokeColor = drawingColour
    let start =
      direction == "bottom"
      ? PixelPoint(x: 0, y: 63)
      : direction == "right" ? PixelPoint(x: 63, y: 0) : .zero
    let strokeCompleted = context.strokeLine(from: start, to: PixelPoint(x: 63, y: 63))
    #expect(strokeCompleted)
  }
  for y in 0..<64 {
    for x in 0..<64 {
      // Straight-edge and exact-diagonal geometric predicates, not a rasterizer.
      let painted =
        direction == "bottom"
        ? y == 63
        : direction == "right" ? x == 63 : x == y
      #expect(pixels[y * 64 + x] == (painted ? drawingPixel : drawingSentinel))
    }
  }
}

@Test(
  "Drawing into zero-width or zero-height contexts writes no pixels",
  arguments: [PixelSize.zero, PixelSize(width: 0, height: 8), PixelSize(width: 8, height: 0)])
func drawingEmptyContext(_ size: PixelSize) {
  var storage = Array(repeating: drawingSentinel, count: 8)
  storage.withUnsafeMutableBufferPointer { buffer in
    #expect(DrawingContext(framebuffer: buffer, contextSize: size, pixelFormat: .bgrx8888) == nil)
  }
  #expect(storage.allSatisfy { $0 == drawingSentinel })
}

@Test(
  "Drawing setPixel replaces RGB and discards source alpha even at zero",
  arguments: [UInt8(0), 1, 127, 128, 254, 255])
func drawingSetPixelAlpha(_ alpha: UInt8) {
  let pixels = drawInGuardedBuffer(size: PixelSize(width: 3, height: 2)) { context in
    #expect(context.setPixel(at: PixelPoint(x: 1, y: 1), to: blendFixtureColour(rgb: 0x12a456, alpha: alpha)))
  }
  #expect(
    pixels == [
      drawingSentinel, drawingSentinel, drawingSentinel,
      drawingSentinel, 0xff12_a456, drawingSentinel,
    ])
}

// Literal rounded channel results, established independently from the source,
// destination and alpha values. No expected result invokes the blend operation.
private let drawingBlendFixtures: [(UInt32, UInt32, UInt8, UInt32)] = [
  // Red over blue, including both fast paths and all requested alpha boundaries.
  (0xff0000, 0xff00_00ff, 0, 0xff00_00ff),
  (0xff0000, 0xff00_00ff, 1, 0xff01_00fe),
  (0xff0000, 0xff00_00ff, 127, 0xff7f_0080),
  (0xff0000, 0xff00_00ff, 128, 0xff80_007f),
  (0xff0000, 0xff00_00ff, 254, 0xfffe_0001),
  (0xff0000, 0xff00_00ff, 255, 0xffff_0000),
  // White over black and black over white.
  (0xffffff, 0xff00_0000, 0, 0xff00_0000),
  (0xffffff, 0xff00_0000, 1, 0xff01_0101),
  (0xffffff, 0xff00_0000, 127, 0xff7f_7f7f),
  (0xffffff, 0xff00_0000, 128, 0xff80_8080),
  (0xffffff, 0xff00_0000, 254, 0xfffe_fefe),
  (0xffffff, 0xff00_0000, 255, 0xffff_ffff),
  (0x000000, 0xffff_ffff, 0, 0xffff_ffff),
  (0x000000, 0xffff_ffff, 1, 0xfffe_fefe),
  (0x000000, 0xffff_ffff, 127, 0xff80_8080),
  (0x000000, 0xffff_ffff, 128, 0xff7f_7f7f),
  (0x000000, 0xffff_ffff, 254, 0xff01_0101),
  (0x000000, 0xffff_ffff, 255, 0xff00_0000),
  // Different RGB channels ensure extraction, weights and rounding are independent.
  (0x12a456, 0xffca_3478, 0, 0xffca_3478),
  (0x12a456, 0xffca_3478, 1, 0xffc9_3478),
  (0x12a456, 0xffca_3478, 127, 0xff6e_6c67),
  (0x12a456, 0xffca_3478, 128, 0xff6e_6c67),
  (0x12a456, 0xffca_3478, 254, 0xff13_a456),
  (0x12a456, 0xffca_3478, 255, 0xff12_a456),
  // A single red unit distinguishes nearest rounding from truncation.
  (0x010000, 0xff00_0000, 127, 0xff00_0000),
  (0x010000, 0xff00_0000, 128, 0xff01_0000),
  // Zero alpha preserves every destination bit; nonzero writes make X opaque.
  (0xffffff, 0x1234_5678, 0, 0x1234_5678),
  (0xffffff, 0x1234_5678, 128, 0xff9a_abbc),
  (0xffffff, 0x1234_5678, 255, 0xffff_ffff),
]

@Test(
  "Drawing blendPixel colour overload uses embedded source alpha with rounded source-over RGB",
  arguments: drawingBlendFixtures)
func drawingBlendColour(_ source: UInt32, _ destination: UInt32, _ alpha: UInt8, _ expected: UInt32) {
  let size = PixelSize(width: 8, height: 6)
  let pixels = drawInGuardedBuffer(size: size, background: destination) { context in
    #expect(context.blendPixel(at: PixelPoint(x: 4, y: 2), to: blendFixtureColour(rgb: source, alpha: alpha)))
  }
  expectDrawingPixels(pixels, size: size, coordinates: [(4, 2)], pixel: expected, background: destination)
}

@Test(
  "Drawing blendPixel explicit alpha overrides tint alpha including transparent tint with full coverage",
  arguments: drawingBlendFixtures, [UInt8(0), 1, 127, 255])
func drawingBlendExplicit(_ sample: (UInt32, UInt32, UInt8, UInt32), _ tintAlpha: UInt8) {
  let (source, destination, alpha, expected) = sample
  let size = PixelSize(width: 8, height: 6)
  let pixels = drawInGuardedBuffer(size: size, background: destination) { context in
    #expect(
      context.blendPixel(
        at: PixelPoint(x: 4, y: 2),
        to: blendFixtureColour(rgb: source, alpha: tintAlpha), withAlpha: alpha))
  }
  expectDrawingPixels(pixels, size: size, coordinates: [(4, 2)], pixel: expected, background: destination)
}

@Test(
  "Drawing both blend overloads address row edges and the first and last panel pixels safely",
  arguments: [
    (PixelPoint(x: 0, y: 0), 0), (PixelPoint(x: 63, y: 0), 63),
    (PixelPoint(x: 0, y: 1), 64), (PixelPoint(x: 63, y: 1), 127),
    (PixelPoint(x: 0, y: 63), 4032), (PixelPoint(x: 63, y: 63), 4095),
  ] as [(PixelPoint, Int)], [false, true])
func drawingBlendBoundaries(_ location: (PixelPoint, Int), _ explicit: Bool) {
  let (point, expectedIndex) = location
  for (alpha, expected): (UInt8, UInt32) in [(0, 0xff00_00ff), (128, 0xff80_007f), (255, 0xffff_0000)] {
    let pixels = drawInGuardedBuffer(size: PixelSize(width: 64, height: 64), background: 0xff00_00ff) { context in
      if explicit {
        #expect(context.blendPixel(at: point, to: blendFixtureColour(rgb: 0xff0000, alpha: 0), withAlpha: alpha))
      } else {
        #expect(context.blendPixel(at: point, to: blendFixtureColour(rgb: 0xff0000, alpha: alpha)))
      }
    }
    for index in pixels.indices {
      #expect(pixels[index] == (index == expectedIndex ? expected : 0xff00_00ff))
    }
  }
}

@Test(
  "Drawing both blend overloads ignore out-of-range coordinates for zero partial and full alpha",
  arguments: [
    PixelPoint(x: -1, y: 0), PixelPoint(x: 0, y: -1),
    PixelPoint(x: 8, y: 0), PixelPoint(x: 0, y: 6), PixelPoint(x: 8, y: 6),
    PixelPoint(x: Int.min, y: 5), PixelPoint(x: 7, y: Int.max),
  ], [false, true])
func drawingBlendClipping(_ point: PixelPoint, _ explicit: Bool) {
  for alpha: UInt8 in [0, 1, 127, 128, 254, 255] {
    let pixels = drawInGuardedBuffer(size: PixelSize(width: 8, height: 6)) { context in
      if explicit {
        #expect(context.blendPixel(at: point, to: .red, withAlpha: alpha))
      } else {
        #expect(context.blendPixel(at: point, to: blendFixtureColour(rgb: 0xff0000, alpha: alpha)))
      }
    }
    #expect(pixels.allSatisfy { $0 == drawingSentinel })
  }
}

@Test(
  "Drawing clipped rectangles honour fill colour alpha with rounded compositing",
  arguments: [
    (UInt8(0), UInt32(0xff00_00ff)), (1, 0xff01_00fe), (127, 0xff7f_0080),
    (128, 0xff80_007f), (254, 0xfffe_0001), (255, 0xffff_0000),
  ] as [(UInt8, UInt32)])
func drawingFillAlpha(_ alpha: UInt8, _ expected: UInt32) {
  let size = PixelSize(width: 4, height: 3)
  let pixels = drawInGuardedBuffer(size: size, background: 0xff00_00ff) { context in
    context.fillColor = blendFixtureColour(rgb: 0xff0000, alpha: alpha)
    let completed = context.fillRect(PixelRect(x: -1, y: 1, width: 3, height: 2))
    #expect(completed)
  }
  expectDrawingPixels(
    pixels, size: size, coordinates: [(0, 1), (1, 1), (0, 2), (1, 2)],
    pixel: expected, background: 0xff00_00ff)
}

@Test("Translucent PixelRect rows finish before the next row checks the deadline", arguments: [1, 56])
func drawingTranslucentPixelRectDeadline(_ visibleWidth: Int) {
  let size = PixelSize(width: 56, height: 3)
  let background: UInt32 = 0xff00_00ff
  let pixels = drawInGuardedBuffer(
    size: size, background: background, renderDeadline: RenderDeadline(timeUs: 100)
  ) { context in
    context.fillColor = PixelColor32(rawValue: 0x80ff_0000)
    RenderHostTime.withTimestamps([99, 100]) {
      let rect = PixelRect(x: -2, y: 0, width: visibleWidth + 2, height: 3)
      let completed = context.fillRect(rect)
      #expect(!completed)
      #expect(context.status == .deadlineExceeded && RenderHostTime.readCount == 2)
      let retried = context.fillRect(rect)
      #expect(!retried)
      #expect(RenderHostTime.readCount == 2)
    }
  }
  for index in pixels.indices {
    #expect(pixels[index] == (index < visibleWidth ? 0xff80_007f : background))
  }
}

@Test(
  "Drawing clipped sloping lines honour stroke alpha without changing the explicit raster",
  arguments: [
    (UInt8(0), UInt32(0xff00_00ff)), (1, 0xff01_00fe), (127, 0xff7f_0080),
    (128, 0xff80_007f), (254, 0xfffe_0001), (255, 0xffff_0000),
  ] as [(UInt8, UInt32)])
func drawingStrokeAlpha(_ alpha: UInt8, _ expected: UInt32) {
  let size = PixelSize(width: 4, height: 3)
  let pixels = drawInGuardedBuffer(size: size, background: 0xff00_00ff) { context in
    context.strokeColor = blendFixtureColour(rgb: 0xff0000, alpha: alpha)
    let strokeCompleted = context.strokeLine(from: PixelPoint(x: -1, y: 0), to: PixelPoint(x: 3, y: 2))
    #expect(strokeCompleted)
  }
  expectDrawingPixels(
    pixels, size: size, coordinates: [(0, 1), (1, 1), (2, 2), (3, 2)],
    pixel: expected, background: 0xff00_00ff)
}

@Test("Drawing successive blends use the previously composited destination")
func drawingSuccessiveBlends() {
  let pixels = drawInGuardedBuffer(size: PixelSize(width: 3, height: 1), background: 0xff00_00ff) { context in
    let point = PixelPoint(x: 1, y: 0)
    #expect(context.blendPixel(at: point, to: blendFixtureColour(rgb: 0xff0000, alpha: 128)))
    #expect(context.framebuffer[1] == 0xff80_007f)
    #expect(context.blendPixel(at: point, to: blendFixtureColour(rgb: 0xff0000, alpha: 0), withAlpha: 128))
  }
  #expect(pixels == [0xff00_00ff, 0xffc0_003f, 0xff00_00ff])
}

private func blendFixtureColour(rgb: UInt32, alpha: UInt8) -> PixelColor32 {
  PixelColor32(red: (rgb >> 16) & 255, green: (rgb >> 8) & 255, blue: rgb & 255, alpha: UInt32(alpha))
}

// A local allocation with four guard words on each side. The context receives
// only the active slice, always exactly width * height pixels as required.
private func drawInGuardedBuffer(
  size: PixelSize, background: UInt32 = drawingSentinel,
  renderDeadline: RenderDeadline? = nil,
  _ draw: (inout DrawingContext) -> Void
) -> [UInt32] {
  let count = size.width * size.height
  let prefix: [UInt32] = [0xdead_beef, 0xcafe_babe, 0x1122_3344, 0x5566_7788]
  let suffix: [UInt32] = [0x99aa_bbcc, 0xddee_ff00, 0xface_feed, 0xbaad_f00d]
  var storage = prefix + Array(repeating: background, count: count) + suffix
  storage.withUnsafeMutableBufferPointer { buffer in
    let active = UnsafeMutableBufferPointer(
      start: buffer.baseAddress!.advanced(by: 4), count: count)
    var context = DrawingContext(
      framebuffer: active, contextSize: size, pixelFormat: .bgrx8888, renderDeadline: renderDeadline)!
    draw(&context)
  }
  #expect(Array(storage.prefix(4)) == prefix)
  #expect(Array(storage.suffix(4)) == suffix)
  return Array(storage[4..<(4 + count)])
}

private func expectDrawingPixels(
  _ pixels: [UInt32], size: PixelSize,
  coordinates: [(Int, Int)], pixel: UInt32 = drawingPixel, background: UInt32 = drawingSentinel
) {
  for y in 0..<size.height {
    for x in 0..<size.width {
      let painted = coordinates.contains { $0.0 == x && $0.1 == y }
      #expect(pixels[y * size.width + x] == (painted ? pixel : background))
    }
  }
}

@Test(
  "Context initialization rejects nonpositive dimensions and insufficient storage without writes",
  arguments: [
    (PixelSize(width: -1, height: 2), 8), (PixelSize(width: 2, height: -1), 8),
    (PixelSize(width: 3, height: 2), 5), (PixelSize(width: 1, height: 1), 0),
  ])
func drawingInvalidSurface(_ size: PixelSize, _ capacity: Int) {
  var storage = Array(repeating: drawingSentinel, count: capacity)
  storage.withUnsafeMutableBufferPointer {
    #expect(DrawingContext(framebuffer: $0, contextSize: size, pixelFormat: .bgrx8888) == nil)
  }
  #expect(storage.allSatisfy { $0 == drawingSentinel })
}

@Test("Context rejects unsupported destination formats without writes", arguments: [PixelFormat.a1, .a8, .pbgra8888])
func drawingUnsupportedPixelFormat(_ format: PixelFormat) {
  var storage = Array(repeating: drawingSentinel, count: 6)
  storage.withUnsafeMutableBufferPointer { buffer in
    #expect(
      DrawingContext(framebuffer: buffer, contextSize: PixelSize(width: 3, height: 2), pixelFormat: format) == nil)
  }
  #expect(storage.allSatisfy { $0 == drawingSentinel })
}

@Test("Context accepts extra capacity but drawing stays within its declared surface")
func drawingExtraCapacity() throws {
  var storage = Array(repeating: drawingSentinel, count: 10)
  try storage.withUnsafeMutableBufferPointer { buffer in
    var context = try #require(
      DrawingContext(framebuffer: buffer, contextSize: PixelSize(width: 3, height: 2), pixelFormat: .bgrx8888))
    #expect(context.pixelFormat == .bgrx8888)
    #expect(context.status == .active && context.canContinue)
    #expect(context.renderDeadline == nil)
    RenderHostTime.withTimestamps([]) {
      let filledSurface = context.fillRect(context.contextFrame)
      #expect(filledSurface)
      let noDeadlineContinues = context.checkDeadline()
      #expect(noDeadlineContinues)
      #expect(RenderHostTime.readCount == 0)
    }
  }
  #expect(Array(storage.prefix(6)) == Array(repeating: UInt32(0xffff_ffff), count: 6))
  #expect(storage.suffix(4).allSatisfy { $0 == drawingSentinel })
}

@Test(
  "Deadline equality or lateness latches status and rejects all later writes without clock reads",
  arguments: [UInt64(100), 101])
func drawingDeadlineStatus(_ now: UInt64) throws {
  var storage = Array(repeating: drawingSentinel, count: 8)
  try storage.withUnsafeMutableBufferPointer { buffer in
    var context = try #require(
      DrawingContext(
        framebuffer: buffer, contextSize: PixelSize(width: 8, height: 1), pixelFormat: .bgrx8888,
        renderDeadline: RenderDeadline(timeUs: 100)))
    #expect(context.status == .active)
    RenderHostTime.withTimestamps([now]) {
      let firstCheck = context.checkDeadline()
      #expect(!firstCheck)
      #expect(context.status == .deadlineExceeded && !context.canContinue)
      let repeatedCheck = context.checkDeadline()
      #expect(!repeatedCheck)
      #expect(!context.setPixel(at: .zero, to: .white))
      #expect(!context.blendPixel(at: .zero, to: .white))
      let laterSpan = context.writeOpaqueSpan(y: 0, from: 0, to: 8, color: .white)
      #expect(!laterSpan)
      let laterStroke = context.strokeLine(from: .zero, to: PixelPoint(x: 7, y: 0))
      #expect(!laterStroke)
      #expect(RenderHostTime.readCount == 1)
    }
  }
  #expect(storage.allSatisfy { $0 == drawingSentinel })
}

@Test("A span finishes once started; expiry rejects the next span without partial pixel writes")
func drawingSpanDeadlineBoundary() throws {
  var storage = Array(repeating: drawingSentinel, count: 16)
  try storage.withUnsafeMutableBufferPointer { buffer in
    var context = try #require(
      DrawingContext(
        framebuffer: buffer, contextSize: PixelSize(width: 8, height: 2), pixelFormat: .bgrx8888,
        renderDeadline: RenderDeadline(timeUs: 100)))
    RenderHostTime.withTimestamps([99, 100]) {
      let firstSpan = context.writeOpaqueSpan(y: 0, from: 0, to: 8, color: .white)
      #expect(firstSpan)
      #expect(context.status == .active && RenderHostTime.readCount == 1)
      let secondSpan = context.writeOpaqueSpan(y: 1, from: 0, to: 8, color: .white)
      #expect(!secondSpan)
      #expect(context.status == .deadlineExceeded && RenderHostTime.readCount == 2)
    }
  }
  #expect(Array(storage.prefix(8)) == Array(repeating: UInt32(0xffff_ffff), count: 8))
  #expect(storage.suffix(8).allSatisfy { $0 == drawingSentinel })
}

@Test("A stroke checks its deadline at the operation boundary, not between pixels")
func drawingStrokeDeadlineBoundary() throws {
  var storage = Array(repeating: drawingSentinel, count: 8)
  try storage.withUnsafeMutableBufferPointer { buffer in
    var context = try #require(
      DrawingContext(
        framebuffer: buffer, contextSize: PixelSize(width: 8, height: 1), pixelFormat: .bgrx8888,
        renderDeadline: RenderDeadline(timeUs: 100)))
    RenderHostTime.withTimestamps([99, 100]) {
      let completedStroke = context.strokeLine(from: .zero, to: PixelPoint(x: 7, y: 0))
      #expect(completedStroke)
      #expect(context.status == .active && RenderHostTime.readCount == 1)
    }
  }
  #expect(storage == Array(repeating: UInt32(0xff00_0000), count: 8))
}

@Test("A translucent span checks its deadline before blending, not between pixels")
func drawingTranslucentSpanDeadlineBoundary() throws {
  var storage = Array(repeating: UInt32(0xff00_00ff), count: 8)
  try storage.withUnsafeMutableBufferPointer { buffer in
    var context = try #require(
      DrawingContext(
        framebuffer: buffer, contextSize: PixelSize(width: 8, height: 1), pixelFormat: .bgrx8888,
        renderDeadline: RenderDeadline(timeUs: 100)))
    context.fillColor = PixelColor32(red: UInt32(255), green: UInt32(0), blue: UInt32(0), alpha: UInt32(128))
    RenderHostTime.withTimestamps([99, 100]) {
      let completedSpan = context.paintSpan(y: 0, from: 0, to: 8)
      #expect(completedSpan)
      #expect(context.status == .active && RenderHostTime.readCount == 1)
    }
  }
  #expect(storage == Array(repeating: UInt32(0xff80_007f), count: 8))
}

@Test(
  "Opaque and translucent spans each check once, finish, then reject the next operation at expiry",
  arguments: [(UInt32(255), UInt32(0xffff_0000)), (128, 0xff80_007f)])
func drawingPaintSpanDeadlineBoundary(_ alpha: UInt32, _ expectedPixel: UInt32) throws {
  var storage = Array(repeating: UInt32(0xff00_00ff), count: 16)
  try storage.withUnsafeMutableBufferPointer { buffer in
    var context = try #require(
      DrawingContext(
        framebuffer: buffer, contextSize: PixelSize(width: 8, height: 2), pixelFormat: .bgrx8888,
        renderDeadline: RenderDeadline(timeUs: 100)))
    context.fillColor = PixelColor32(red: UInt32(255), green: UInt32(0), blue: UInt32(0), alpha: alpha)
    RenderHostTime.withTimestamps([99, 100]) {
      let completed = context.paintSpan(y: 0, from: 0, to: 8)
      #expect(completed)
      #expect(context.canContinue && context.status == .active)
      #expect(RenderHostTime.readCount == 1)
      let expired = context.paintSpan(y: 1, from: 0, to: 8)
      #expect(!expired)
      #expect(!context.canContinue && context.status == .deadlineExceeded)
      #expect(RenderHostTime.readCount == 2)
      let rejected = context.paintSpan(y: 0, from: 0, to: 8)
      #expect(!rejected)
      #expect(context.status == .deadlineExceeded && RenderHostTime.readCount == 2)
    }
  }
  #expect(Array(storage.prefix(8)) == Array(repeating: expectedPixel, count: 8))
  #expect(storage.suffix(8).allSatisfy { $0 == 0xff00_00ff })
}

@Test(
  "Overflowing surface dimensions are rejected without trapping or writing the framebuffer",
  arguments: [
    PixelSize(width: Int.max, height: 2), PixelSize(width: 2, height: Int.max),
    PixelSize(width: Int.max, height: Int.max), PixelSize(width: Int.max / 2 + 1, height: 2),
  ])
func drawingSurfaceDimensionOverflow(_ size: PixelSize) {
  var storage = Array(repeating: drawingSentinel, count: 8)
  storage.withUnsafeMutableBufferPointer { buffer in
    RenderHostTime.withTimestamps([]) {
      #expect(
        DrawingContext(framebuffer: buffer, contextSize: size, pixelFormat: .bgrx8888, renderDeadline: .distant) == nil)
      #expect(RenderHostTime.readCount == 0)
    }
  }
  #expect(storage.allSatisfy { $0 == drawingSentinel })
}

@Test("Fractional quads retain subpixel shifts rather than rounding vertices")
func fractionalQuads() {
  let size = PixelSize(width: 8, height: 8)
  let expected = [(2, 2), (3, 2), (2, 3), (3, 3)]
  let pixels = drawInGuardedBuffer(size: size) { context in
    context.fillColor = drawingColour
    let quadCompleted = context.fillQuad(
      DrawingQuad(vertices: [
        DrawingPoint(x: 1.25, y: 1.25), DrawingPoint(x: 3.25, y: 1.25),
        DrawingPoint(x: 3.25, y: 3.25), DrawingPoint(x: 1.25, y: 3.25),
      ]))
    #expect(quadCompleted)
    expectDrawingPixels(Array(context.framebuffer), size: size, coordinates: expected)
    let offscreenQuadCompleted = context.fillQuad(
      DrawingQuad(vertices: [
        DrawingPoint(x: -20, y: -20), DrawingPoint(x: -10, y: -20),
        DrawingPoint(x: -10, y: -10), DrawingPoint(x: -20, y: -10),
      ]))
    #expect(offscreenQuadCompleted)
    let emptyCircleCompleted = context.fillCircle(centre: DrawingPoint(x: 3.5, y: 3.5), radius: 0)
    #expect(emptyCircleCompleted)
  }
  expectDrawingPixels(pixels, size: size, coordinates: expected)
}

@Test("A sloping quad includes the pixel at an exact integer edge intersection")
func quadIntegerEdgeIntersection() {
  let size = PixelSize(width: 32, height: 8)
  let quad = DrawingQuad(vertices: [
    DrawingPoint(x: 0, y: 0), DrawingPoint(x: 25, y: 5),
    DrawingPoint(x: 30, y: 5), DrawingPoint(x: 30, y: 0),
  ])
  let pixels = drawInGuardedBuffer(size: size) { context in
    context.fillColor = drawingColour
    let completed = context.fillQuad(quad)
    #expect(completed)
  }

  // At y = 3, multiplying before dividing gives exactly 15 on the left edge.
  let row = 3 * size.width
  for x in 0..<size.width {
    #expect(pixels[row + x] == ((15..<30).contains(x) ? drawingPixel : drawingSentinel))
  }
}

@Test("Binary circles include cardinal boundary pixels")
func drawingBinaryCircle() {
  let size = PixelSize(width: 7, height: 7)
  let pixels = drawInGuardedBuffer(size: size) { context in
    context.fillColor = drawingColour
    let completed = context.fillCircle(centre: DrawingPoint(x: 3, y: 3), radius: 2)
    #expect(completed)
  }
  expectDrawingPixels(
    pixels, size: size,
    coordinates: [
      (3, 1), (2, 2), (3, 2), (4, 2), (1, 3), (2, 3), (3, 3), (4, 3), (5, 3), (2, 4), (3, 4), (4, 4), (3, 5),
    ])
}

@Test("Binary quads include left edges, exclude right edges and skip zero-width tips")
func drawingBinarySlopingQuad() {
  let size = PixelSize(width: 7, height: 7)
  let pixels = drawInGuardedBuffer(size: size) { context in
    context.fillColor = drawingColour
    let completed = context.fillQuad(
      DrawingQuad(vertices: [
        DrawingPoint(x: 3, y: 1), DrawingPoint(x: 5, y: 3),
        DrawingPoint(x: 3, y: 5), DrawingPoint(x: 1, y: 3),
      ]))
    #expect(completed)
  }
  expectDrawingPixels(
    pixels, size: size, coordinates: [(2, 2), (3, 2), (1, 3), (2, 3), (3, 3), (4, 3), (2, 4), (3, 4)])
}

@Test(
  "Binary circles and fractional quads clip without overwriting framebuffer guards",
  arguments: [false, true], [false, true])
func drawingBinaryShapeClipping(_ circle: Bool, _ lowerRight: Bool) {
  let size = PixelSize(width: 5, height: 5)
  let pixels = drawInGuardedBuffer(size: size) { context in
    context.fillColor = drawingColour
    if circle {
      let coordinate: Float = lowerRight ? 4 : 0
      let completed = context.fillCircle(centre: DrawingPoint(x: coordinate, y: coordinate), radius: 2)
      #expect(completed)
    } else {
      let start: Float = lowerRight ? 2.25 : -1.25
      let end: Float = lowerRight ? 6.25 : 2.25
      let completed = context.fillQuad(
        DrawingQuad(vertices: [
          DrawingPoint(x: start, y: start), DrawingPoint(x: end, y: start),
          DrawingPoint(x: end, y: end), DrawingPoint(x: start, y: end),
        ]))
      #expect(completed)
    }
  }
  let visible =
    circle
    ? [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (0, 2)]
    : [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2)]
  // The fractional quad starts at column/row 3 after rounding up.
  let coordinates =
    lowerRight
    ? (circle ? visible.map { (4 - $0.0, 4 - $0.1) } : [(3, 3), (4, 3), (3, 4), (4, 4)])
    : visible
  expectDrawingPixels(pixels, size: size, coordinates: coordinates)
}

private let coverageBackground: UInt32 = 0xff00_00ff

@Test("A clipped translucent quad blends its visible rows and leaves neighbouring pixels intact")
func drawingClippedTranslucentQuad() {
  let quad = DrawingQuad(vertices: [
    DrawingPoint(x: -1, y: 1), DrawingPoint(x: 3, y: 1),
    DrawingPoint(x: 3, y: 4), DrawingPoint(x: -1, y: 4),
  ])
  let size = PixelSize(width: 4, height: 3)
  let pixels = drawInGuardedBuffer(
    size: size, background: coverageBackground, renderDeadline: RenderDeadline(timeUs: 100)
  ) { context in
    context.fillColor = PixelColor32(rawValue: 0x80ff_0000)
    RenderHostTime.withTimestamps([99, 99, 100]) {
      let completed = context.fillQuad(quad)
      #expect(completed)
      #expect(context.canContinue && RenderHostTime.readCount == 2)
    }
  }
  expectDrawingPixels(
    pixels, size: size, coordinates: [(0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2)],
    pixel: 0xff80_007f, background: coverageBackground)
}

@Test(
  "Constant coverage spans select the operation colour and paint half-open bounds",
  arguments: [
    (.fill, 0, 255, 0xff00_00ff),
    (.fill, 128, 255, 0xff80_007f),
    (.fill, 255, 255, 0xffff_0000),
    (.stroke, 0, 128, 0xff00_00ff),
    (.stroke, 128, 128, 0xff00_40bf),
    (.stroke, 255, 128, 0xff00_807f),
    (.stroke, 254, 254, 0xff00_fd02),
    // With source alpha 128, coverage 1 and 3 round up to effective alpha 1 and 2.
    (.stroke, 1, 128, 0xff00_01fe),
    (.stroke, 2, 128, 0xff00_01fe),
    (.stroke, 3, 128, 0xff00_02fd),
  ] as [(DrawingOperation, UInt8, UInt8, UInt32)])
func constantCoverageSpan(_ operation: DrawingOperation, _ coverage: UInt8, _ alpha: UInt8, _ expected: UInt32) {
  let pixels = drawInGuardedBuffer(size: PixelSize(width: 4, height: 2), background: coverageBackground) { context in
    context.fillColor = .red
    context.strokeColor = blendFixtureColour(rgb: 0x00ff00, alpha: alpha)
    let completed = context.paintSpan(y: 1, from: 1, to: 3, coverage: coverage, operation: operation)
    #expect(completed)
  }
  #expect(
    pixels == [
      coverageBackground, coverageBackground, coverageBackground, coverageBackground,
      coverageBackground, expected, expected, coverageBackground,
    ])
}

@Test("Preclipped constant coverage spans paint up to both horizontal framebuffer edges")
func constantCoverageSpanEdges() {
  let pixels = drawInGuardedBuffer(size: PixelSize(width: 4, height: 2), background: coverageBackground) { context in
    context.fillColor = .red
    let leftCompleted = context.paintSpan(y: 0, from: 0, to: 2, coverage: 255, operation: .fill)
    let rightCompleted = context.paintSpan(y: 1, from: 2, to: 4, coverage: 128, operation: .fill)
    #expect(leftCompleted)
    #expect(rightCompleted)
  }
  #expect(
    pixels == [
      0xffff_0000, 0xffff_0000, coverageBackground, coverageBackground,
      coverageBackground, coverageBackground, 0xff80_007f, 0xff80_007f,
    ])
}

@Test(
  "Preclipped variable coverage spans apply each supplied sample and combine opacity once",
  arguments: [
    (.fill, 0, [0, 64, 128, 255], [0xff00_00ff, 0xff40_00bf, 0xff80_007f, 0xffff_0000]),
    (.stroke, 0, [0, 1, 3, 255], [0xff00_00ff, 0xff00_01fe, 0xff00_02fd, 0xff00_807f]),
    (.stroke, 2, [128, 255], [0xff00_00ff, 0xff00_00ff, 0xff00_40bf, 0xff00_807f]),
  ] as [(DrawingOperation, Int, [UInt8], [UInt32])])
func variableCoverageSpan(_ operation: DrawingOperation, _ x: Int, _ coverage: [UInt8], _ expected: [UInt32]) {
  let pixels = drawInGuardedBuffer(size: PixelSize(width: 4, height: 1), background: coverageBackground) { context in
    context.fillColor = .red
    context.strokeColor = blendFixtureColour(rgb: 0x00ff00, alpha: 128)
    let completed = context.paintSpan(y: 0, from: x, coverage: coverage.span, operation: operation)
    #expect(completed)
  }
  #expect(pixels == expected)
}

@Test(
  "Obvious constant coverage no-ops leave the deadline unchecked",
  arguments: [
    ("zero coverage", 0, 2, 0, 255),
    ("transparent source", 0, 2, 255, 0),
    ("alpha rounds to zero", 0, 2, 127, 1),
  ] as [(String, Int, Int, UInt8, UInt8)])
func constantCoverageSpanNoWork(_ name: String, _ x: Int, _ endX: Int, _ coverage: UInt8, _ alpha: UInt8) {
  let pixels = drawInGuardedBuffer(
    size: PixelSize(width: 4, height: 1), background: coverageBackground, renderDeadline: RenderDeadline(timeUs: 100)
  ) { context in
    context.fillColor = blendFixtureColour(rgb: 0xff0000, alpha: alpha)
    RenderHostTime.withTimestamps([100]) {
      let completed = context.paintSpan(y: 0, from: x, to: endX, coverage: coverage, operation: .fill)
      #expect(completed, "\(name)")
      #expect(RenderHostTime.readCount == 0 && context.canContinue, "\(name)")
    }
  }
  #expect(pixels == Array(repeating: coverageBackground, count: 4))
}

@Test(
  "Obvious variable coverage no-ops leave the deadline unchecked",
  arguments: [
    ("empty at the right edge", 4, [], 255),
    ("transparent source", 0, [255, 128], 0),
  ] as [(String, Int, [UInt8], UInt8)])
func variableCoverageSpanNoWork(_ name: String, _ x: Int, _ coverage: [UInt8], _ alpha: UInt8) {
  let pixels = drawInGuardedBuffer(
    size: PixelSize(width: 4, height: 1), background: coverageBackground, renderDeadline: RenderDeadline(timeUs: 100)
  ) { context in
    context.strokeColor = blendFixtureColour(rgb: 0x00ff00, alpha: alpha)
    RenderHostTime.withTimestamps([100]) {
      let completed = context.paintSpan(y: 0, from: x, coverage: coverage.span, operation: .stroke)
      #expect(completed, "\(name)")
      #expect(RenderHostTime.readCount == 0 && context.canContinue, "\(name)")
    }
  }
  #expect(pixels == Array(repeating: coverageBackground, count: 4))
}

private enum EmptySpanSource: CaseIterable, Sendable {
  case constantCoverage
  case translucentConstantCoverage
  case clippedQuad
  case clippedCircle
}

@Test(
  "An empty span can reach a deadline checkpoint without writing pixels",
  arguments: EmptySpanSource.allCases, [UInt64(99), 100])
private func drawingEmptySpanDeadline(_ source: EmptySpanSource, _ now: UInt64) {
  let pixels = drawInGuardedBuffer(
    size: PixelSize(width: 4, height: 1), background: coverageBackground, renderDeadline: RenderDeadline(timeUs: 100)
  ) { context in
    let quad = DrawingQuad(vertices: [
      DrawingPoint(x: 5, y: -1), DrawingPoint(x: 7, y: -1),
      DrawingPoint(x: 7, y: 1), DrawingPoint(x: 5, y: 1),
    ])
    RenderHostTime.withTimestamps([now, 100]) {
      let completed: Bool
      switch source {
      case .constantCoverage:
        completed = context.paintSpan(y: 0, from: 4, to: 4, coverage: 255, operation: .fill)
      case .translucentConstantCoverage:
        completed = context.paintSpan(y: 0, from: 4, to: 4, coverage: 128, operation: .fill)
      case .clippedQuad:
        completed = context.fillQuad(quad)
      case .clippedCircle:
        completed = context.fillCircle(centre: DrawingPoint(x: 6, y: 0), radius: 1)
      }
      let expectedCompletion = now < 100
      #expect(completed == expectedCompletion)
      #expect(context.status == (expectedCompletion ? .active : .deadlineExceeded))
      #expect(RenderHostTime.readCount == 1)

      let next = context.writeOpaqueSpan(y: 0, from: 0, to: 1, color: .white)
      #expect(!next)
      #expect(context.status == .deadlineExceeded)
      #expect(RenderHostTime.readCount == (expectedCompletion ? 2 : 1))
    }
  }
  #expect(pixels == Array(repeating: coverageBackground, count: 4))
}

@Test("Single-pixel constant and variable coverage agree at the right edge")
func coverageSpanSinglePixel() {
  let pixels = drawInGuardedBuffer(size: PixelSize(width: 2, height: 2), background: coverageBackground) { context in
    context.fillColor = .red
    context.strokeColor = blendFixtureColour(rgb: 0x00ff00, alpha: 128)
    let coverage: [UInt8] = [128]
    let constant = context.paintSpan(y: 0, from: 1, to: 2, coverage: 128, operation: .stroke)
    let variable = context.paintSpan(y: 1, from: 1, coverage: coverage.span, operation: .stroke)
    #expect(constant)
    #expect(variable)
  }
  #expect(pixels == [coverageBackground, 0xff00_40bf, coverageBackground, 0xff00_40bf])
}

@Test(
  "Variable coverage inspection can meet or miss the deadline without painting",
  arguments: [
    ("zero coverage", [0, 0], 0..<2, 255),
    ("nonzero coverage clipped away", [255, 0], 1..<2, 255),
    ("alpha rounds to zero", [0, 127], 0..<2, 1),
  ] as [(String, [UInt8], Range<Int>, UInt8)],
  [UInt64(99), 100])
func variableCoverageSpanInspectionDeadline(_ sample: (String, [UInt8], Range<Int>, UInt8), _ now: UInt64) {
  let (name, coverage, visibleSamples, alpha) = sample
  let deadline = RenderDeadline(timeUs: 100)
  let expectedCompletion = now < deadline.timeUs
  let pixels = drawInGuardedBuffer(
    size: PixelSize(width: 4, height: 1), background: coverageBackground, renderDeadline: deadline
  ) { context in
    context.strokeColor = blendFixtureColour(rgb: 0x00ff00, alpha: alpha)
    RenderHostTime.withTimestamps([now]) {
      // Only inspecting the visible samples reveals that there is no ink to paint.
      let completed = context.paintSpan(
        y: 0, from: 0, coverage: coverage.span.extracting(visibleSamples), operation: .stroke)
      #expect(completed == expectedCompletion, "\(name)")
      #expect(RenderHostTime.readCount == 1, "\(name)")
      #expect(context.status == (expectedCompletion ? .active : .deadlineExceeded), "\(name)")
    }
  }
  #expect(pixels == Array(repeating: coverageBackground, count: 4))
}

@Test(
  "Constant and uniform variable coverage paint the same pixels and stop at deadline expiry",
  arguments: [false, true], [(UInt8(128), UInt32(0xff80_007f)), (255, 0xffff_0000)])
func coverageSpanDeadline(_ variable: Bool, _ sample: (UInt8, UInt32)) {
  let (coverage, expected) = sample
  let coverages = [coverage, coverage, coverage]
  func paintRow(_ y: Int, into context: inout DrawingContext) -> Bool {
    if variable {
      return context.paintSpan(y: y, from: 0, coverage: coverages.span, operation: .fill)
    }
    return context.paintSpan(y: y, from: 0, to: 3, coverage: coverage, operation: .fill)
  }

  let pixels = drawInGuardedBuffer(
    size: PixelSize(width: 3, height: 3), background: coverageBackground, renderDeadline: RenderDeadline(timeUs: 100)
  ) { context in
    context.fillColor = .red
    RenderHostTime.withTimestamps([99, 100]) {
      let completed = paintRow(0, into: &context)
      #expect(completed)
      #expect(RenderHostTime.readCount == 1 && context.canContinue)
      let expired = paintRow(1, into: &context)
      #expect(!expired)
      #expect(RenderHostTime.readCount == 2 && context.status == .deadlineExceeded)
      let rejected = paintRow(2, into: &context)
      #expect(!rejected)
      #expect(RenderHostTime.readCount == 2 && context.status == .deadlineExceeded)
    }
  }
  #expect(
    pixels == [
      expected, expected, expected,
      coverageBackground, coverageBackground, coverageBackground,
      coverageBackground, coverageBackground, coverageBackground,
    ])
}

private let rectangleFixtureSize = PixelSize(width: 5, height: 4)
private let rectangleFixtureBackground = (0..<20).map { 0xff12_3456 + UInt32($0) * 0x0003_0507 }

private func drawRectangleFixture(
  source: UInt32, deadline: RenderDeadline? = nil, _ draw: (inout DrawingContext) -> Void
) -> [UInt32] {
  drawInGuardedBuffer(size: rectangleFixtureSize, renderDeadline: deadline) { context in
    for (index, pixel) in rectangleFixtureBackground.enumerated() {
      context.framebuffer[index] = pixel
    }
    context.fillColor = PixelColor32(rawValue: source)
    context.strokeColor = .green
    draw(&context)
  }
}

private func rectangleReference(_ rect: DrawingRect, source: UInt32) -> [UInt32] {
  let left = Double(rect.origin.x)
  let top = Double(rect.origin.y)
  let right = Double(rect.origin.x + rect.size.width)
  let bottom = Double(rect.origin.y + rect.size.height)
  let sourceAlpha = Double(source >> 24)

  return rectangleFixtureBackground.enumerated().map { index, background in
    let x = Double(index % rectangleFixtureSize.width)
    let y = Double(index / rectangleFixtureSize.width)
    // Intersect this unit pixel square directly with the requested rectangle.
    let width = max(0, min(right, x + 1) - max(left, x))
    let height = max(0, min(bottom, y + 1) - max(top, y))
    let coverage = (width * height * 255).rounded(.toNearestOrAwayFromZero)
    let effectiveAlpha = (coverage * sourceAlpha / 255).rounded(.toNearestOrAwayFromZero)
    guard effectiveAlpha > 0 else { return background }

    let weight = effectiveAlpha / 255
    var pixel: UInt32 = 0xff00_0000
    for shift in [16, 8, 0] {
      let ink = Double((source >> shift) & 255)
      let backdrop = Double((background >> shift) & 255)
      let channel = (ink * weight + backdrop * (1 - weight)).rounded(.toNearestOrAwayFromZero)
      pixel |= UInt32(channel) << shift
    }
    return pixel
  }
}

@Test(
  "Drawing rectangles match independent unit-square coverage and RGB compositing",
  arguments: [
    ("aligned", DrawingRect(x: 1, y: 1, width: 3, height: 2)),
    ("fractional horizontal edges", DrawingRect(x: 0.25, y: 1, width: 3.5, height: 2)),
    ("fractional vertical edges", DrawingRect(x: 1, y: 0.25, width: 3, height: 2.5)),
    ("all four corners", DrawingRect(x: 0.4375, y: 0.4375, width: 3.125, height: 2.125)),
    ("half offset unit square", DrawingRect(x: 0.5, y: 0.5, width: 1, height: 1)),
    ("quarter offset unit square", DrawingRect(x: 0.25, y: 0.25, width: 1, height: 1)),
    ("narrow column", DrawingRect(x: 1.25, y: 0.5, width: 0.25, height: 2.75)),
    ("short row", DrawingRect(x: 0.375, y: 2.125, width: 4, height: 0.625)),
    ("inside one pixel", DrawingRect(x: 2.25, y: 1.125, width: 0.5, height: 0.75)),
    ("two partial columns", DrawingRect(x: 1.75, y: 1, width: 0.5, height: 2)),
    ("two partial rows", DrawingRect(x: 2, y: 1.75, width: 2, height: 0.5)),
    ("clipped at top left", DrawingRect(x: -0.75, y: -0.5, width: 3.125, height: 2.75)),
    ("clipped at bottom right", DrawingRect(x: 3.375, y: 2.625, width: 3.25, height: 2.5)),
    ("ends at right and bottom", DrawingRect(x: 2.25, y: 1.75, width: 2.75, height: 2.25)),
    ("covers framebuffer", DrawingRect(x: -0.5, y: -0.5, width: 6, height: 5)),
    ("coverage rounds to zero", DrawingRect(x: 2, y: 1, width: 1.0 / 1024, height: 1)),
    ("coverage rounds to full", DrawingRect(x: 2, y: 1, width: 511.0 / 512, height: 1)),
  ],
  [UInt32(0xffcd_6b29), 0x81cd_6b29, 0x00cd_6b29])
func drawingAnalyticalRectangleCoverage(_ fixture: (String, DrawingRect), _ source: UInt32) {
  let (name, rect) = fixture
  let pixels = drawRectangleFixture(source: source) { context in
    let completed = context.fillRect(rect)
    #expect(completed)
  }
  let expected = rectangleReference(rect, source: source)
  for index in pixels.indices {
    #expect(pixels[index] == expected[index], "\(name), pixel index \(index)")
  }
}

@Test(
  "Opaque integer-aligned drawing rectangles match pixel rectangles",
  arguments: [
    PixelRect(x: 1, y: 1, width: 3, height: 2),
    PixelRect(x: 0, y: 0, width: 5, height: 4),
    PixelRect(x: -1, y: 2, width: 7, height: 4),
    PixelRect(x: 4, y: 3, width: 1, height: 1),
  ])
func drawingAnalyticalRectanglePixelParity(_ rect: PixelRect) {
  let source: UInt32 = 0xffcd_6b29
  let drawingRect = DrawingRect(
    x: Float(rect.minX), y: Float(rect.minY), width: Float(rect.width), height: Float(rect.height))
  let pixel = drawRectangleFixture(source: source) { context in
    let completed = context.fillRect(rect)
    #expect(completed)
  }
  let analytical = drawRectangleFixture(source: source) { context in
    #expect(context.drawingFrame == DrawingRect(x: 0, y: 0, width: 5, height: 4))
    let completed = context.fillRect(drawingRect)
    #expect(completed)
  }
  #expect(analytical == pixel)
  #expect(analytical == rectangleReference(drawingRect, source: source))
}

@Test(
  "Empty, degenerate and fully clipped drawing rectangles leave the framebuffer untouched",
  arguments: [
    DrawingRect.zero,
    DrawingRect(x: 1.25, y: 0.5, width: 0, height: 2),
    DrawingRect(x: 1.25, y: 0.5, width: 2, height: 0),
    DrawingRect(x: 1.25, y: 0.5, width: -0.25, height: 2),
    DrawingRect(x: 1.25, y: 0.5, width: 2, height: -0.25),
    DrawingRect(x: 1, y: 1, width: .nan, height: 1),
    DrawingRect(x: 1, y: 1, width: 1, height: .infinity),
    DrawingRect(x: -1.25, y: 0.5, width: 1.25, height: 1),
    DrawingRect(x: 0.5, y: -2, width: 1, height: 1.5),
    DrawingRect(x: 5, y: 0.5, width: 2, height: 1),
    DrawingRect(x: 0.5, y: 4, width: 1, height: 2),
  ])
func drawingAnalyticalRectangleNoPixels(_ rect: DrawingRect) {
  let pixels = drawRectangleFixture(source: 0xffcd_6b29, deadline: RenderDeadline(timeUs: 100)) { context in
    RenderHostTime.withTimestamps([100]) {
      let completed = context.fillRect(rect)
      #expect(completed)
      #expect(context.canContinue && RenderHostTime.readCount == 0)
    }
  }
  #expect(pixels == rectangleFixtureBackground)
}

@Test(
  "Drawing rectangle deadline cancellation preserves complete rows and unwritten pixels",
  arguments: [
    DrawingRect(x: 0.25, y: 0.25, width: 3.5, height: 2.5),
    DrawingRect(x: 0.25, y: 0.25, width: 0.5, height: 2.5),
  ],
  [0, 1, 2])
func drawingAnalyticalRectangleDeadline(_ rect: DrawingRect, _ completedRows: Int) {
  let source: UInt32 = 0x81cd_6b29
  let timestamps = Array(repeating: UInt64(99), count: completedRows) + [100]
  let pixels = drawRectangleFixture(source: source, deadline: RenderDeadline(timeUs: 100)) { context in
    RenderHostTime.withTimestamps(timestamps) {
      let completed = context.fillRect(rect)
      #expect(!completed)
      #expect(context.status == .deadlineExceeded)
      #expect(RenderHostTime.readCount == timestamps.count)

      let retry = context.fillRect(DrawingRect(x: 0, y: 0, width: 5, height: 4))
      #expect(!retry)
      #expect(context.status == .deadlineExceeded && RenderHostTime.readCount == timestamps.count)
    }
  }

  let rendered = rectangleReference(rect, source: source)
  let rowEnd = completedRows * rectangleFixtureSize.width
  let expected = Array(rendered.prefix(rowEnd)) + rectangleFixtureBackground.dropFirst(rowEnd)
  #expect(pixels == expected)
}
