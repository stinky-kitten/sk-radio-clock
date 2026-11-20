//
//  Renderer.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-01.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import SKLSHUB75

struct Renderer<Face: ClockFace> {

  private var clockFace: Face

  init(clockFace: Face) {
    self.clockFace = clockFace
  }

  mutating func setClockFace(_ face: Face) {
    clockFace = face
  }

  func render(_ request: inout HUB75RenderRequest, displaySnapshot: MSFDisplaySnapshot) -> Bool {
    guard let framebuffer = request.framebuffer else { return false }

    let buffer = UnsafeMutableBufferPointer(
      start: framebuffer,
      count: Int(request.width) * Int(request.height)
    )

    let size = PixelSize(width: Int(request.width), height: Int(request.height))
    guard
      var drawingContext = DrawingContext(
        framebuffer: buffer,
        contextSize: size,
        pixelFormat: .bgrx8888,
        renderDeadline: RenderDeadline(timeUs: request.deadline_us))
    else { return false }

    let completed = clockFace.render(
      into: &drawingContext,
      displaySnapshot: displaySnapshot
    )

    return completed && drawingContext.status == .active
  }
}
