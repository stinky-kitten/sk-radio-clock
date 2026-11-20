//
//  DrawingGeometry.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-11-10.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct DrawingPoint: Sendable, Equatable {
  let x: Float
  let y: Float

  static let zero = DrawingPoint(x: 0, y: 0)
}

struct DrawingSize: Sendable, Equatable {
  let width: Float
  let height: Float

  static let zero = DrawingSize(width: 0, height: 0)
}

struct DrawingRect: Sendable, Equatable {
  let origin: DrawingPoint
  let size: DrawingSize

  static let zero = DrawingRect(origin: .zero, size: .zero)
}

struct DrawingQuad: Sendable {
  let vertices: InlineArray<4, DrawingPoint>
}

extension DrawingRect {
  var minX: Float { origin.x }
  var minY: Float { origin.y }
  var maxX: Float { origin.x + size.width }
  var maxY: Float { origin.y + size.height }

  var width: Float { size.width }
  var height: Float { size.height }

  var isEmpty: Bool { !(width > 0 && height > 0) }

  init(x: Float, y: Float, width: Float, height: Float) {
    self.origin = DrawingPoint(x: x, y: y)
    self.size = DrawingSize(width: width, height: height)
  }

  func insetBy(dx: Float, dy: Float) -> DrawingRect {
    return DrawingRect(
      x: origin.x + dx, y: origin.y + dy,
      width: size.width - 2 * dx, height: size.height - 2 * dy
    )
  }

  func intersection(_ other: DrawingRect) -> DrawingRect? {
    let left = max(minX, other.minX)
    let top = max(minY, other.minY)
    let right = min(maxX, other.maxX)
    let bottom = min(maxY, other.maxY)

    guard right > left, bottom > top else {
      return nil
    }

    return DrawingRect(
      x: left,
      y: top,
      width: right - left,
      height: bottom - top
    )
  }
}

/// Extensions to convert between pixel and drawing coordinates.

extension PixelPoint {
  var drawingCentre: DrawingPoint {
    DrawingPoint(
      x: Float(x) + 0.5,
      y: Float(y) + 0.5
    )
  }
}

extension DrawingPoint {
  var pixelContainingPoint: PixelPoint? {
    guard
      let pixelX = Int(exactly: x.rounded(.down)),
      let pixelY = Int(exactly: y.rounded(.down))
    else {
      return nil
    }

    return PixelPoint(x: pixelX, y: pixelY)
  }
}

extension PixelRect {
  var drawingRect: DrawingRect {
    DrawingRect(
      x: Float(origin.x),
      y: Float(origin.y),
      width: Float(size.width),
      height: Float(size.height)
    )
  }
}
