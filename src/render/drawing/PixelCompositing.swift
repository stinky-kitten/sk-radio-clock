//
//  PixelCompositing.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-11-13.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension DrawingContext {
  /// Writes a preclipped horizontal span of opaque pixels.
  /// The caller guarantees valid framebuffer coordinates.
  /// Source alpha is ignored.
  @discardableResult
  mutating func writeOpaqueSpan(y: Int, from left: Int, to right: Int, color: PixelColor32) -> Bool {
    guard checkDeadline() else { return false }

    let offset = y * contextSize.width
    let pixel = color.xrgb8888

    for x in left..<right {
      framebuffer[offset + x] = pixel
    }
    return true
  }

  @discardableResult
  mutating func writeBlendedSpan(
    y: Int,
    from left: Int,
    to right: Int,
    color: PixelColor32,
    effectiveAlpha: UInt8
  ) -> Bool {
    guard checkDeadline() else { return false }

    let blend = PreparedBlend(color: color, alpha: effectiveAlpha)
    let offset = y * contextSize.width

    for x in left..<right {
      let index = offset + x
      framebuffer[index] = blend.blend(over: framebuffer[index])
    }

    return true
  }
}

struct PreparedBlend {
  let red: UInt32
  let green: UInt32
  let blue: UInt32
  let inverseAlpha: UInt32

  init(color: PixelColor32, alpha: UInt8) {
    let sourceAlpha = UInt32(alpha)

    red = color.red * sourceAlpha
    green = color.green * sourceAlpha
    blue = color.blue * sourceAlpha

    inverseAlpha = 255 - sourceAlpha
  }

  @inline(__always)
  func blend(over destination: UInt32) -> UInt32 {
    guard inverseAlpha != 255 else { return destination }

    let dstColor = PixelColor32(rawValue: destination)
    let outRed = (red + dstColor.red * inverseAlpha + 127) / 255
    let outGreen = (green + dstColor.green * inverseAlpha + 127) / 255
    let outBlue = (blue + dstColor.blue * inverseAlpha + 127) / 255

    return (outRed << 16) | (outGreen << 8) | outBlue | 0xff00_0000
  }
}
