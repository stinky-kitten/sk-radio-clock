//
//  DrawingContext.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-02.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

/// Drawing operations check the optional render deadline before
/// modifying the framebuffer.
///
/// Once the deadline has expired, the context records that state
/// and subsequent drawing operations are rejected.
///
/// Deadlines are not checked during an individual drawing operation.
/// An operation that starts before the deadline is allowed to finish,
/// even if the deadline expires while it is executing.
///
/// Callers should inspect the context status after rendering.

struct DrawingContext {

  enum Status {
    case active
    case deadlineExceeded
  }

  private(set) var status: Status = .active
  let framebuffer: UnsafeMutableBufferPointer<UInt32>
  let pixelFormat: PixelFormat
  let contextSize: PixelSize
  let renderDeadline: RenderDeadline?

  var fillColor: PixelColor32 = .white
  var strokeColor: PixelColor32 = .black

  init?(
    framebuffer: UnsafeMutableBufferPointer<UInt32>,
    contextSize: PixelSize,
    pixelFormat: PixelFormat,
    renderDeadline: RenderDeadline? = nil
  ) {
    guard pixelFormat == .bgrx8888, contextSize.width > 0, contextSize.height > 0 else { return nil }

    let (requiredPixels, overflow) =
      contextSize.width.multipliedReportingOverflow(by: contextSize.height)
    guard !overflow, framebuffer.count >= requiredPixels else { return nil }

    self.framebuffer = framebuffer
    self.pixelFormat = pixelFormat
    self.contextSize = contextSize
    self.renderDeadline = renderDeadline
  }

  var canContinue: Bool { status == .active }

  mutating func checkDeadline() -> Bool {
    // Without a deadline, drawing cannot enter a failed state.
    guard let renderDeadline else { return true }
    guard status == .active else { return false }

    if renderDeadline.hasExpired {
      self.status = .deadlineExceeded
      return false
    }
    return true
  }

  var contextFrame: PixelRect { PixelRect(origin: .zero, size: contextSize) }
  var drawingFrame: DrawingRect { contextFrame.drawingRect }
}

/// Painting operations that actually paint colour to the framebuffer
extension DrawingContext {
  @discardableResult
  func setPixel(at point: PixelPoint, to color: PixelColor32) -> Bool {
    guard canContinue else { return false }
    guard
      point.x >= 0 && point.x < contextSize.width
        && point.y >= 0 && point.y < contextSize.height
    else { return true }

    framebuffer[point.y * contextSize.width + point.x] = color.xrgb8888
    return true
  }

  @discardableResult
  func blendPixel(at point: PixelPoint, to color: PixelColor32) -> Bool {
    return blendPixel(at: point, to: color, withAlpha: UInt8(color.alpha))
  }

  @discardableResult
  func blendPixel(at point: PixelPoint, to tint: PixelColor32, withAlpha alpha: UInt8) -> Bool {
    guard canContinue else { return false }
    guard
      alpha > 0
        && point.x >= 0 && point.x < contextSize.width && point.y >= 0 && point.y < contextSize.height
    else { return true }

    guard alpha < 255 else { return setPixel(at: point, to: tint) }

    let offset = point.y * contextSize.width + point.x

    // XRGB8888: blend directly into the opaque framebuffer.
    let srcAlpha = UInt32(alpha)
    let dstAlpha = 255 - srcAlpha

    let dstColor = PixelColor32(rawValue: framebuffer[offset])

    let outRed = (tint.red * srcAlpha + dstColor.red * dstAlpha + 127) / 255
    let outGreen = (tint.green * srcAlpha + dstColor.green * dstAlpha + 127) / 255
    let outBlue = (tint.blue * srcAlpha + dstColor.blue * dstAlpha + 127) / 255

    framebuffer[offset] = (outRed << 16) | (outGreen << 8) | outBlue | 0xff00_0000
    return true
  }
}
