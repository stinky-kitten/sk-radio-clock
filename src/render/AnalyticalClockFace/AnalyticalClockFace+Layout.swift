//
//  AnalyticalClockFace+Layout.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-02.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension AnalyticalClockFace {
  struct LayoutMetrics {

    let panelSize: PixelSize

    let indicatorFrame: PixelRect
    let traceFrame: PixelRect
    let bitsFrame: PixelRect

    static let bitSlotCount: Int = 6
    static let bitSlotWidth: Int = 10
    static let bitLeadingSpace: Int = 2

    let clockFrame: PixelRect
    let clockBaseline: Int

    let dateFrame: PixelRect

    let timeZoneFrame: PixelRect

    init(size: PixelSize) {
      self.panelSize = size
      let margin = 2

      let indicatorSize = 4
      self.indicatorFrame = PixelRect(
        x: panelSize.width - margin - indicatorSize,
        y: margin,
        width: indicatorSize,
        height: indicatorSize
      )

      let traceHeight = 7
      self.traceFrame = PixelRect(
        x: margin,
        y: self.indicatorFrame.maxY + margin,
        width: panelSize.width - (2 * margin),
        height: traceHeight
      )

      bitsFrame = PixelRect(
        x: traceFrame.minX,
        y: traceFrame.maxY,
        width: traceFrame.size.width,
        height: 8
      )

      self.clockFrame = PixelRect(
        x: 0,
        y: bitsFrame.maxY + 2,
        width: panelSize.width,
        height: 22
      )

      self.clockBaseline = size.height - 22  // 42 on 64×64

      let desiredDateBaseline = size.height - 12  // 52
      dateFrame = PixelRect(
        x: margin,
        y: desiredDateBaseline - PixelOperator8Font.ascent,
        width: panelSize.width - (2 * margin),
        height: PixelOperator8Font.lineHeight
      )

      let desiredTimeZoneBaseline = size.height - margin  // 62
      let timeZoneClearWidth = 20
      timeZoneFrame = PixelRect(
        x: size.width - margin - timeZoneClearWidth,  // 20 is a maximum width guess
        y: desiredTimeZoneBaseline - PixelOperator8Font.ascent,
        width: timeZoneClearWidth,
        height: PixelOperator8Font.lineHeight
      )
    }

    var dateBaseline: Int {
      dateFrame.maxY - PixelOperator8Font.descent
    }

    var timeZoneBaseline: Int {
      timeZoneFrame.maxY - PixelOperator8Font.descent
    }
  }
}
