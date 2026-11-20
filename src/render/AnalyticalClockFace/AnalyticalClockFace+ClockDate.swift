//
//  AnalyticalClockFace+ClockDate.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-08.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension AnalyticalClockFace {
  func drawClockDate(
    into context: inout DrawingContext,
    clockSnapshot: ClockSnapshot,
    theme: Theme
  ) -> Bool {
    var charValues: InlineArray<12, UInt32> = .init(repeating: 0)
    let charCount = clockSnapshot.unicodeValuesForDateMonthYear(policy: .evidence, into: &charValues)
    let text = charValues.span.extracting(first: charCount)

    let dateFrame = layoutMetrics.dateFrame
    let xOffset = dateFrame.minX + (dateFrame.width - PixelOperator8Font.advance(of: text)) / 2

    return clockSnapshot.drawDate(
      text,
      into: &context,
      xOffset: xOffset,
      baselineY: layoutMetrics.dateBaseline,
      clippedTo: dateFrame,
      theme: theme,
      policy: .evidence)
  }
}
