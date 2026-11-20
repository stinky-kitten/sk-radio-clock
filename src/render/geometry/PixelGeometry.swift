//
//  PixelGeometry.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-20.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct PixelPoint: Equatable {
  let x: Int
  let y: Int

  static let zero = PixelPoint(x: 0, y: 0)
}

struct PixelSize: Equatable {
  let width: Int
  let height: Int

  static let zero: PixelSize = PixelSize(width: 0, height: 0)
}

struct PixelRect: Equatable {
  let origin: PixelPoint
  let size: PixelSize

  func insetBy(dx: Int, dy: Int) -> PixelRect {
    return PixelRect(
      x: origin.x + dx, y: origin.y + dy,
      width: size.width - 2 * dx, height: size.height - 2 * dy
    )
  }

  func intersection(_ other: PixelRect) -> PixelRect? {
    let left = max(minX, other.minX)
    let top = max(minY, other.minY)
    let right = min(maxX, other.maxX)
    let bottom = min(maxY, other.maxY)

    guard right > left, bottom > top else {
      return nil
    }

    return PixelRect(
      x: left,
      y: top,
      width: right - left,
      height: bottom - top
    )
  }

  static let zero = PixelRect(origin: .zero, size: .zero)
}

extension PixelRect {
  var minX: Int { origin.x }
  var minY: Int { origin.y }
  var maxX: Int { origin.x + size.width }
  var maxY: Int { origin.y + size.height }

  var width: Int { size.width }
  var height: Int { size.height }

  var isEmpty: Bool { !(width > 0 && height > 0) }

  init(x: Int, y: Int, width: Int, height: Int) {
    self.origin = PixelPoint(x: x, y: y)
    self.size = PixelSize(width: width, height: height)
  }
}
