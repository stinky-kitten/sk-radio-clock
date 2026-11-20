//
//  PixelCompositingTests.swift
//  sk-radio-clock
//
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

@Test(
  "Prepared blends match integer RGB compositing when reused across opaque destinations",
  arguments: [UInt32(0xff00_0000), 0xffff_ffff, 0x00ff_0000, 0x8000_ff00, 0xfe00_00ff, 0x3712_a456],
  [UInt8(0), 1, 2, 127, 128, 254, 255])
func preparedBlendEquivalence(_ source: UInt32, _ alpha: UInt8) throws {
  let color = PixelColor32(rawValue: source)
  let prepared = PreparedBlend(color: color, alpha: alpha)
  // At effective alpha zero both paths leave the destination word unchanged.
  let destinations: [UInt32] = [
    0xff00_0000, 0xffff_ffff, 0xffff_0000, 0xff00_ff00, 0xff00_00ff,
    0xffca_3478, 0xff01_fe83, 0xfff1_091d,
  ]
  var framebuffer = destinations
  try framebuffer.withUnsafeMutableBufferPointer { buffer in
    let context = try #require(
      DrawingContext(
        framebuffer: buffer, contextSize: PixelSize(width: destinations.count, height: 1), pixelFormat: .bgrx8888))
    for (index, destination) in destinations.enumerated() {
      let expected = preparedBlendReference(source: source, destination: destination, alpha: alpha)
      let actual = prepared.blend(over: destination)
      #expect(actual == expected, "Destination index \(index)")
      #expect(actual >> 24 == 255)
      let completed = context.blendPixel(at: PixelPoint(x: index, y: 0), to: color, withAlpha: alpha)
      #expect(completed)
      #expect(actual == buffer[index], "Destination index \(index)")
    }
  }
}

@Test("A prepared blend with zero effective alpha preserves the entire destination word")
func preparedBlendTransparentDestinationWord() {
  let destination: UInt32 = 0x3412_a456
  let blend = PreparedBlend(color: .red, alpha: 0)
  #expect(blend.blend(over: destination) == destination)
}

@Test(
  "Prepared blends round a single channel unit across the half-way threshold",
  arguments: [
    (127, 0xff00_0001),
    (128, 0xff01_0000),
  ] as [(UInt8, UInt32)])
func preparedBlendRounding(_ alpha: UInt8, _ expected: UInt32) {
  let color = PixelColor32(rawValue: 0x0001_0000)
  let actual = PreparedBlend(color: color, alpha: alpha).blend(over: 0xff00_0001)
  #expect(actual == expected)
}

private func preparedBlendReference(source: UInt32, destination: UInt32, alpha: UInt8) -> UInt32 {
  let opacity = Int(alpha)
  var result: UInt32 = 0xff00_0000
  for shift in [16, 8, 0] {
    let sourceChannel = Int((source >> shift) & 255)
    let destinationChannel = Int((destination >> shift) & 255)
    let channel = (sourceChannel * opacity + destinationChannel * (255 - opacity) + 127) / 255
    result |= UInt32(channel) << shift
  }
  return result
}
