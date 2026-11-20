//
//  AnalyticalClockFace+Indicator.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-02.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension AnalyticalClockFace {
  func drawIndicator(
    into context: inout DrawingContext,
    signalHigh: Bool,
    theme: Theme
  ) -> Bool {
    // Raw physical level: bright HIGH, dim LOW, independent of RF polarity.
    context.fillColor = signalHigh ? theme.indicatorHighColor : theme.indicatorLowColor

    return context.fillRect(layoutMetrics.indicatorFrame)
  }
}
