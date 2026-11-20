//
//  ClockSnapshot+Render.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-11-03.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension ClockSnapshot {
  func draw24HourTime<Theme: EpistemicPalette & TimeTextTheme>(
    _ characters: borrowing Span<UInt32>,
    into context: inout DrawingContext,
    xOffset: Int,
    baselineY: Int,
    clippedTo frame: PixelRect,
    theme: Theme,
    policy: ClockDisplayPolicy
  ) -> Bool {
    var pen = PixelPoint(x: xOffset, y: baselineY)

    for index in characters.indices {
      guard
        let scalar = Unicode.Scalar(characters[index]),
        let glyph = ClockFont.glyph(for: scalar)
      else { return false }

      let color: PixelColor32
      if index == 2 {
        color = theme.timeSeparatorColor
      } else {
        let isHour = index < 2
        let state = isHour ? clockState.hour : clockState.minute
        let available =
          isHour ? calendarDateTime.hour != nil : calendarDateTime.minute != nil

        color = theme.color(
          for: presentationState(
            for: state,
            available: available,
            policy: policy
          )
        )
      }

      pen = context.drawGlyph(
        glyph,
        atPen: pen,
        color: color,
        clippedTo: frame
      )

      guard context.canContinue else { return false }
    }

    return true
  }
}

extension ClockSnapshot {
  func drawDate<Theme: EpistemicPalette>(
    _ characters: borrowing Span<UInt32>,
    into context: inout DrawingContext,
    xOffset: Int,
    baselineY: Int,
    clippedTo frame: PixelRect,
    theme: Theme,
    policy: ClockDisplayPolicy
  ) -> Bool {
    let monthLength = characters.count - 8
    let yearStart = 4 + monthLength

    var pen = PixelPoint(x: xOffset, y: baselineY)

    for index in characters.indices {
      guard let scalar = Unicode.Scalar(characters[index]),
        let glyph = PixelOperator8Font.glyph(for: scalar)
      else { return false }

      // Spaces separate the fields but have no visible colour.
      // We could add a isWhitespace to the glyph type but for now we can just check the scalar value.
      if scalar.value == 0x20 {
        pen = PixelPoint(x: pen.x + glyph.advance, y: pen.y)
        continue
      }

      let state: EpistemicState
      let available: Bool
      if index < 2 {
        state = clockState.dayOfMonth
        available = calendarDateTime.dayOfMonth != nil
      } else if index < yearStart {
        state = clockState.month
        available = calendarDateTime.month != nil
      } else {
        state = clockState.year
        available = calendarDateTime.year != nil
      }

      pen = context.drawGlyph(
        glyph,
        atPen: pen,
        color: theme.color(
          for: presentationState(
            for: state,
            available: available,
            policy: policy
          )
        ),
        clippedTo: frame
      )

      guard context.canContinue else { return false }
    }

    return true
  }
}

extension ClockSnapshot {
  func presentationState(
    for state: EpistemicState,
    available: Bool,
    policy: ClockDisplayPolicy
  ) -> EpistemicState {
    guard available else { return .unknown }

    switch policy {
    case .evidence:
      return state

    case .clock:
      return hasAcquiredTime ? .confirmed : state
    }
  }
}
