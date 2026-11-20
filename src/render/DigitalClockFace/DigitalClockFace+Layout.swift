//
//  DigitalClockFace+Layout.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-30.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension DigitalClockFace {
  struct LayoutMetrics {

    let panelSize: PixelSize

    let indicatorFrame: PixelRect

    let timeFrame: PixelRect

    let secondsFrame: PixelRect

    let dayOfWeekFrame: PixelRect

    let dateFrame: PixelRect

    init(size: PixelSize) {
      self.panelSize = size
      let margin = 4

      let indicatorSize = 4
      self.indicatorFrame = PixelRect(
        x: panelSize.width - margin - indicatorSize + 1,
        y: margin - 1,
        width: indicatorSize,
        height: indicatorSize
      )

      self.timeFrame = PixelRect(
        x: margin - 1, y: margin,
        width: panelSize.width - 2 * margin + 2,
        height: ClockFont.lineHeight)

      self.secondsFrame = PixelRect(
        x: margin, y: size.height - 39,
        width: panelSize.width - 2 * margin,
        height: PixelOperator8Font.lineHeight)

      self.dayOfWeekFrame = PixelRect(
        x: margin, y: size.height - 28,
        width: panelSize.width - 2 * margin,
        height: PixelOperator8Font.lineHeight)

      self.dateFrame = PixelRect(
        x: margin, y: size.height - 16,
        width: panelSize.width - 2 * margin,
        height: PixelOperator8Font.lineHeight)
    }

    var timeBaseline: Int {
      timeFrame.maxY - ClockFont.descent
    }

    var secondsBaseline: Int {
      secondsFrame.maxY - PixelOperator8Font.descent
    }

    var dayOfWeekBaseline: Int {
      dayOfWeekFrame.maxY - PixelOperator8Font.descent
    }

    var dateBaseline: Int {
      dateFrame.maxY - PixelOperator8Font.descent
    }
  }
}
