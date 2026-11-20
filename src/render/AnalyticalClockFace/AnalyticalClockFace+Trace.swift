//
//  AnalyticalClockFace+Trace.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-02.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension AnalyticalClockFace {
  func drawTrace(
    into context: inout DrawingContext,
    displaySnapshot: MSFDisplaySnapshot,
    theme: AnalyticalClockFace.Theme
  ) {

    enum TraceLevel {
      case high
      case low
    }
    let traceFrame = layoutMetrics.traceFrame

    context.fillColor = theme.traceBackgroundColor
    guard context.fillRect(traceFrame) else { return }

    context.strokeColor = theme.pulseColor

    let traceHighY = traceFrame.minY
    let traceLowY = traceFrame.maxY - 1
    var runStart: Int?
    var runLevel: TraceLevel?

    for bin in 0..<MSFDisplaySnapshot.binCount {
      let bit = UInt64(1) << bin
      let high = displaySnapshot.highBins & bit != 0
      let low = displaySnapshot.lowBins & bit != 0
      let x = traceFrame.minX + bin

      switch (high, low) {
      case (true, false):
        // HIGH only
        if runLevel == .high {
          // Continue existing HIGH run.
        } else {
          if runStart != nil {
            guard
              strokeRun(
                from: runStart, to: x - 1, level: runLevel, into: &context,
                highY: traceHighY, lowY: traceLowY)
            else { return }

            // Previous definite state was LOW: draw the edge.
            guard
              context.strokeLine(
                from: PixelPoint(x: x, y: traceLowY),
                to: PixelPoint(x: x, y: traceHighY)
              )
            else { return }
          }

          runStart = x
          runLevel = .high
        }
      case (false, true):
        // LOW only
        if runLevel == .low {
          // Continue existing LOW run.
        } else {
          if runStart != nil {
            guard
              strokeRun(
                from: runStart, to: x - 1, level: runLevel, into: &context,
                highY: traceHighY, lowY: traceLowY)
            else { return }

            // Previous definite state was HIGH: draw the edge.
            guard
              context.strokeLine(
                from: PixelPoint(x: x, y: traceHighY),
                to: PixelPoint(x: x, y: traceLowY)
              )
            else { return }
          }

          runStart = x
          runLevel = .low
        }

      case (true, true):
        // Both levels occurred somewhere within this 100 ms bin
        // Finish any definite run before this mixed bin.
        if runStart != nil {
          guard
            strokeRun(
              from: runStart, to: x - 1, level: runLevel, into: &context,
              highY: traceHighY, lowY: traceLowY)
          else { return }
        }

        // We know both levels occurred during this bin, but not exactly when.
        guard
          context.strokeLine(
            from: PixelPoint(x: x, y: traceHighY),
            to: PixelPoint(x: x, y: traceLowY)
          )
        else { return }

        runStart = nil
        runLevel = nil

      case (false, false):
        // Unknown/no data: deliberately break the waveform.
        if runStart != nil {
          guard
            strokeRun(
              from: runStart, to: x - 1, level: runLevel, into: &context,
              highY: traceHighY, lowY: traceLowY)
          else { return }
        }
        runStart = nil
        runLevel = nil
      }
    }

    if runStart != nil {
      guard
        strokeRun(
          from: runStart, to: traceFrame.minX + MSFDisplaySnapshot.binCount - 1,
          level: runLevel, into: &context, highY: traceHighY, lowY: traceLowY)
      else { return }
    }

    // Explicit inputs avoid heap-boxing mutable captures in unoptimised builds.
    func strokeRun(
      from startX: Int?, to endX: Int, level: TraceLevel?, into context: inout DrawingContext,
      highY: Int, lowY: Int
    ) -> Bool {
      guard let startX, let level else { return true }

      let y = level == .high ? highY : lowY

      return context.strokeLine(
        from: PixelPoint(x: startX, y: y),
        to: PixelPoint(x: endX, y: y)
      )
    }
  }
}
