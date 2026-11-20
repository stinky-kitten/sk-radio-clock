//
//  AnalyticalClockFace+Bits.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-02.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension AnalyticalClockFace {
  func drawBits(
    into context: inout DrawingContext,
    displaySnapshot: MSFDisplaySnapshot,
    theme: Theme
  ) {
    let bitsFrame = layoutMetrics.bitsFrame

    context.fillColor = theme.traceBackgroundColor
    guard context.fillRect(bitsFrame) else { return }

    guard let phaseOffset = displaySnapshot.secondPhaseBin else {
      return
    }

    for slot in 0..<MSFDisplaySnapshot.secondCount {
      guard let text = text(for: displaySnapshot.seconds[slot]) else {
        continue
      }

      _ = context.drawString(
        text,
        font: MSFBitFont.self,
        atPen: penForBitSlot(slot, phaseOffset: phaseOffset),
        color: theme.bitsColor,
        clippedTo: bitsFrame
      )
      guard context.canContinue else { return }
    }

    // The current unfinished second waiting to enter the completed history.
    _ = context.drawString(
      "? ?",
      font: MSFBitFont.self,
      atPen: penForBitSlot(MSFDisplaySnapshot.secondCount, phaseOffset: phaseOffset),
      color: theme.bitsColor,
      clippedTo: bitsFrame
    )

    func penForBitSlot(_ slot: Int, phaseOffset: Int) -> PixelPoint {
      PixelPoint(
        x: bitsFrame.minX
          + slot * LayoutMetrics.bitSlotWidth
          + LayoutMetrics.bitLeadingSpace
          - phaseOffset,
        y: bitsFrame.maxY)
    }
  }

  private func text(
    for second: MSFDisplaySecond
  ) -> StaticString? {
    switch second {
    case .absent:
      return nil

    case .unknown:
      return "? ?"

    case .decoded(.minuteMarker):
      return "M M"

    case .decoded(.bits(let bits)):
      switch (bits.a, bits.b) {
      case (false, false):
        return "0 0"

      case (false, true):
        return "0 1"

      case (true, false):
        return "1 0"

      case (true, true):
        return "1 1"
      }
    }
  }
}
