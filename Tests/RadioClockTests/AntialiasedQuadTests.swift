import Testing

@testable import RadioClockLogic

private let quadFramebufferSize = PixelSize(width: 4, height: 4)
private let quadBlack: UInt32 = 0xff00_0000

private func makeQuad(_ a: (Float, Float), _ b: (Float, Float), _ c: (Float, Float), _ d: (Float, Float)) -> DrawingQuad
{
  DrawingQuad(vertices: [
    DrawingPoint(x: a.0, y: a.1), DrawingPoint(x: b.0, y: b.1),
    DrawingPoint(x: c.0, y: c.1), DrawingPoint(x: d.0, y: d.1),
  ])
}

@Test(
  "Antialiased quads paint known cell areas in either winding",
  arguments: [
    (
      makeQuad((0, 0), (4, 0), (4, 3), (0, 3)),
      [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 0]
    ),
    (
      makeQuad((0.25, 0.5), (2.75, 0.5), (2.75, 2), (0.25, 2)),
      [96, 128, 96, 0, 191, 255, 191, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    ),
    (
      makeQuad((2, 0), (4, 2), (2, 4), (0, 2)),
      [0, 128, 128, 0, 128, 255, 255, 128, 128, 255, 255, 128, 0, 128, 128, 0]
    ),
    (makeQuad((0, 0), (3, 3), (3, 3.5), (0, 0.5)), [96, 0, 0, 0, 32, 96, 0, 0, 0, 32, 96, 0, 0, 0, 32, 0]),
    (makeQuad((0.5, 0.125), (0.875, 0.5), (0.5, 0.875), (0.125, 0.5)), [72] + Array(repeating: 0, count: 15)),
    (
      makeQuad((-0.5, 0.5), (2.25, 0.5), (2.25, 2.5), (-0.5, 2.5)),
      [128, 128, 32, 0, 255, 255, 64, 0, 128, 128, 32, 0, 0, 0, 0, 0]
    ),
    (makeQuad((2.5, 2.5), (5, 2.5), (5, 5), (2.5, 5)), [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 128, 0, 0, 128, 255]),
  ])
func antialiasedQuadKnownAreas(_ quad: DrawingQuad, _ expected: [Int]) throws {
  let vertices = quad.vertices
  let reversed = DrawingQuad(vertices: [vertices[0], vertices[3], vertices[2], vertices[1]])
  for winding in [quad, reversed] {
    var pixels = Array(repeating: quadBlack, count: 16)
    try pixels.withUnsafeMutableBufferPointer { framebuffer in
      var context = try #require(
        DrawingContext(framebuffer: framebuffer, contextSize: quadFramebufferSize, pixelFormat: .bgrx8888))
      context.fillColor = .blue
      var row = InlineArray<4, UInt8>(repeating: 0)
      var scratch = row.mutableSpan
      #expect(context.fillAntialiasedQuad(winding, coverageRow: &scratch))
    }
    #expect(pixels == expected.map { quadBlack | UInt32($0) })
  }
}

@Test("A fractional skewed quad conserves its geometric area within coverage rounding")
func antialiasedQuadAreaConservation() throws {
  let quad = makeQuad((0.25, 0.375), (3.625, 0.75), (3.25, 3.375), (0.625, 2.875))
  var pixels = Array(repeating: quadBlack, count: 16)
  try pixels.withUnsafeMutableBufferPointer { framebuffer in
    var context = try #require(
      DrawingContext(framebuffer: framebuffer, contextSize: quadFramebufferSize, pixelFormat: .bgrx8888))
    context.fillColor = .blue
    var row = InlineArray<4, UInt8>(repeating: 0)
    var scratch = row.mutableSpan
    #expect(context.fillAntialiasedQuad(quad, coverageRow: &scratch))
  }
  let area = Float(pixels.reduce(0) { $0 + ($1 & 255) }) / 255
  // Splitting along the first-to-third vertex diagonal gives areas 9/2 and 51/16.
  #expect(abs(area - 123.0 / 16) <= 16 * 0.5 / 255)
}

@Test(
  "Offscreen, invalid and degenerate antialiased quads are no-ops",
  arguments: [
    makeQuad((-3, 0), (-1, 0), (-1, 2), (-3, 2)),
    makeQuad((0, 4), (2, 4), (2, 5), (0, 5)),
    makeQuad((0, 0), (1, 1), (2, 2), (3, 3)),
    makeQuad((0, 0), (1, 0), (1, 0), (0, 1)),
    makeQuad((0, 0), (3, 0), (1, 1), (0, 3)),
    makeQuad((0, 0), (2, 2), (2, 0), (0, 2)),
    makeQuad((.nan, 0), (2, 0), (2, 2), (0, 2)),
    makeQuad((0, 0), (.infinity, 0), (2, 2), (0, 2)),
  ])
func antialiasedQuadNoOp(_ quad: DrawingQuad) throws {
  let background: UInt32 = 0xff40_3020
  var pixels = Array(repeating: background, count: 16)
  try pixels.withUnsafeMutableBufferPointer { framebuffer in
    var context = try #require(
      DrawingContext(
        framebuffer: framebuffer, contextSize: quadFramebufferSize, pixelFormat: .bgrx8888,
        renderDeadline: RenderDeadline(timeUs: 100)))
    var row = InlineArray<4, UInt8>(repeating: 0)
    var scratch = row.mutableSpan
    RenderHostTime.withTimestamps([100]) {
      #expect(context.fillAntialiasedQuad(quad, coverageRow: &scratch))
      #expect(context.status == .active && RenderHostTime.readCount == 0)
    }
  }
  #expect(pixels.allSatisfy { $0 == background })
}

@Test("Translucent quads composite both full and fractional pixels over the destination")
func antialiasedQuadAlpha() throws {
  let background: UInt32 = 0xff00_00ff
  var pixels = Array(repeating: background, count: 16)
  let quad = makeQuad((0.5, 0), (2.25, 0), (2.25, 1), (0.5, 1))
  try pixels.withUnsafeMutableBufferPointer { framebuffer in
    var context = try #require(
      DrawingContext(framebuffer: framebuffer, contextSize: quadFramebufferSize, pixelFormat: .bgrx8888))
    context.fillColor = PixelColor32(rawValue: 0x80ff_0000)
    var row = InlineArray<4, UInt8>(repeating: 0)
    var scratch = row.mutableSpan
    #expect(context.fillAntialiasedQuad(quad, coverageRow: &scratch))
  }
  // Coverage bytes [128, 255, 64] yield effective alphas [64, 128, 32].
  #expect(Array(pixels.prefix(4)) == [0xff40_00bf, 0xff80_007f, 0xff20_00df, background])
  #expect(pixels.dropFirst(4).allSatisfy { $0 == background })
}

@Test(
  "Quad deadline expiry completes a row and leaves all subsequent rows untouched",
  arguments: [
    (makeQuad((0.25, 0), (3.75, 0), (3.75, 3), (0.25, 3)), [191, 255, 255, 191]),
    (makeQuad((0.25, 0), (0.75, 0), (0.75, 3), (0.25, 3)), [128, 0, 0, 0]),
  ])
func antialiasedQuadDeadline(_ quad: DrawingQuad, _ firstRow: [Int]) throws {
  var pixels = Array(repeating: quadBlack, count: 16)
  try pixels.withUnsafeMutableBufferPointer { framebuffer in
    var context = try #require(
      DrawingContext(
        framebuffer: framebuffer, contextSize: quadFramebufferSize, pixelFormat: .bgrx8888,
        renderDeadline: RenderDeadline(timeUs: 100)))
    context.fillColor = .blue
    var row = InlineArray<4, UInt8>(repeating: 0)
    var scratch = row.mutableSpan
    RenderHostTime.withTimestamps([99, 100]) {
      #expect(!context.fillAntialiasedQuad(quad, coverageRow: &scratch))
      #expect(context.status == .deadlineExceeded && RenderHostTime.readCount == 2)
      #expect(!context.fillAntialiasedQuad(quad, coverageRow: &scratch))
      #expect(RenderHostTime.readCount == 2)
    }
  }
  #expect(Array(pixels.prefix(4)) == firstRow.map { quadBlack | UInt32($0) })
  #expect(pixels.dropFirst(4).allSatisfy { $0 == quadBlack })
}
