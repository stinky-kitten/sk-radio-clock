//
//  AnalyticalClockFace+ClockTime.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-02.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension AnalyticalClockFace {
  func drawClockTime(
    into context: inout DrawingContext,
    clockSnapshot: ClockSnapshot,
    theme: Theme
  ) -> Bool {
    let timeFrame = layoutMetrics.clockFrame

    var charValues: InlineArray<5, UInt32> = .init(repeating: 0)
    clockSnapshot.unicodeValuesFor24HourTime(policy: .evidence, into: &charValues)

    // Centering the time string horizontally within the clock frame.
    let xOffset =
      timeFrame.minX + (timeFrame.width - ClockFont.advance(of: charValues.span)) / 2

    return clockSnapshot.draw24HourTime(
      charValues.span,
      into: &context,
      xOffset: xOffset,
      baselineY: layoutMetrics.clockBaseline,
      clippedTo: timeFrame,
      theme: theme,
      policy: .evidence)
  }
}
