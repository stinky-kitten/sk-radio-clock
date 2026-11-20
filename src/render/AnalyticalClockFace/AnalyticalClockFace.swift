//
//  AnalyticalClockFace.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-02.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct AnalyticalClockFace: ClockFace {

  let layoutMetrics: LayoutMetrics
  let configuration: ClockConfiguration
  let theme: Theme

  func render(
    into drawingContext: inout DrawingContext,
    displaySnapshot: MSFDisplaySnapshot
  ) -> Bool {

    drawingContext.fillColor = theme.backgroundColor
    if !drawingContext.fillRect(drawingContext.contextFrame) { return false }

    guard
      drawIndicator(
        into: &drawingContext,
        signalHigh: displaySnapshot.signalHigh,
        theme: theme
      )
    else { return false }

    drawTrace(
      into: &drawingContext,
      displaySnapshot: displaySnapshot,
      theme: theme
    )
    guard drawingContext.canContinue else { return false }

    drawBits(
      into: &drawingContext,
      displaySnapshot: displaySnapshot,
      theme: theme
    )
    guard drawingContext.canContinue else { return false }

    guard
      drawClockTime(
        into: &drawingContext,
        clockSnapshot: displaySnapshot.clockSnapshot,
        theme: theme
      )
    else { return false }

    guard
      drawClockDate(
        into: &drawingContext,
        clockSnapshot: displaySnapshot.clockSnapshot,
        theme: theme
      )
    else { return false }

    drawTimeZone(
      into: &drawingContext,
      clockSnapshot: displaySnapshot.clockSnapshot,
      theme: theme
    )

    return drawingContext.canContinue
  }
}

extension AnalyticalClockFace {
  init(size: PixelSize, configuration: ClockConfiguration) {
    let theme: Theme

    switch configuration.theme {
    case .standard:
      theme = .standard
    }

    self.init(
      layoutMetrics: LayoutMetrics(size: size),
      configuration: configuration,
      theme: theme
    )
  }
}
