//
//  AnalyticalClockFace+TimeZone.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-08.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension AnalyticalClockFace {
  func drawTimeZone(
    into context: inout DrawingContext,
    clockSnapshot: ClockSnapshot,
    theme: Theme
  ) {
    let state = clockSnapshot.clockState.timeZone

    //context.fillColor = theme.backgroundColor
    //context.fillRect(layoutMetrics.timeZoneFrame)

    guard state != .unknown,
      let timeZone = clockSnapshot.calendarDateTime.timeZone
    else { return }

    let text = timeZone.abbreviation
    let advance = PixelOperator8Font.advance(of: text)

    _ = context.drawString(
      text,
      font: PixelOperator8Font.self,
      atPen: PixelPoint(
        x: layoutMetrics.timeZoneFrame.maxX - advance,
        y: layoutMetrics.timeZoneBaseline
      ),
      color: theme.color(for: state),
      clippedTo: layoutMetrics.timeZoneFrame
    )
  }
}
