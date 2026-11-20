//
//  AnalogueClockFace+Layout.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-20.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

#if SWIFT_PACKAGE
  import Foundation
#endif

extension AnalogueClockFace {
  struct LayoutMetrics {
    let panelSize: PixelSize

    let centre: DrawingPoint
    let dialRadius: Float
    let indicatorFrame: PixelRect

    init(size: PixelSize) {
      precondition(size.width > 0 && size.height > 0)

      panelSize = size

      // Native geometry uses unit pixel cells, so the panel spans [0, width).
      centre = DrawingPoint(
        x: Float(size.width) / 2,
        y: Float(size.height) / 2
      )

      dialRadius = Float(min(size.width, size.height) - 1) / 2

      indicatorFrame = PixelRect(
        x: size.width - 6,
        y: 2,
        width: 4,
        height: 4
      )
    }

    // Preserve existing clock proportions when scaling the dial.
    var geometryScale: Float { dialRadius / 31.5 }
    var bezelWidth: Float { 1.5 * geometryScale }
    var faceRadius: Float { dialRadius - bezelWidth }

    var majorMarkerInnerRadius: Float { 23.5 * geometryScale }
    var minorMarkerInnerRadius: Float { 25.5 * geometryScale }
    var markerOuterRadius: Float { 28.5 * geometryScale }

    var majorMarkerWidth: Float { 2 * geometryScale }
    var minorMarkerWidth: Float { 1.5 * geometryScale }

    struct HandDimensions {
      let innerRadius: Float
      let outerRadius: Float
      let width: Float
    }

    var hourHand: HandDimensions {
      HandDimensions(
        innerRadius: -2 * geometryScale,
        outerRadius: 16 * geometryScale,
        width: 4 * geometryScale
      )
    }

    var minuteHand: HandDimensions {
      HandDimensions(
        innerRadius: -2 * geometryScale,
        outerRadius: 23 * geometryScale,
        width: 2.5 * geometryScale
      )
    }

    var secondHand: HandDimensions {
      HandDimensions(
        innerRadius: -4 * geometryScale,
        outerRadius: 26 * geometryScale,
        width: 1 * geometryScale
      )
    }

    var centreBossRadius: Float {
      2.5 * geometryScale
    }

    func radialRectangle(
      angle: Float, dimensions: HandDimensions
    ) -> DrawingQuad {
      radialRectangle(
        angle: angle,
        innerRadius: dimensions.innerRadius,
        outerRadius: dimensions.outerRadius,
        width: dimensions.width
      )
    }

    /// A rectangular radial stroke, in output coordinates. Zero points upwards;
    /// positive angles rotate clockwise. No integer rounding occurs here.
    func radialRectangle(
      angle: Float, innerRadius: Float, outerRadius: Float, width: Float
    ) -> DrawingQuad {
      let dx = sinf(angle)
      let dy = -cosf(angle)
      let px = -dy * width / 2
      let py = dx * width / 2
      let startX = centre.x + dx * innerRadius
      let startY = centre.y + dy * innerRadius
      let endX = centre.x + dx * outerRadius
      let endY = centre.y + dy * outerRadius
      return DrawingQuad(vertices: [
        DrawingPoint(x: startX + px, y: startY + py),
        DrawingPoint(x: endX + px, y: endY + py),
        DrawingPoint(x: endX - px, y: endY - py),
        DrawingPoint(x: startX - px, y: startY - py),
      ])
    }
  }
}
