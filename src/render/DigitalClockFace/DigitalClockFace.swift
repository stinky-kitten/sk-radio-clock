//
//  DigitalClockFace.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-30.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct DigitalClockFace: ClockFace {

  let layoutMetrics: LayoutMetrics
  let configuration: ClockConfiguration
  let theme: Theme

  func render(
    into context: inout DrawingContext,
    displaySnapshot: MSFDisplaySnapshot
  ) -> Bool {

    context.fillColor = theme.backgroundColor
    guard context.fillRect(context.contextFrame) else { return false }

    let snapshot = displaySnapshot.clockSnapshot

    // The MSF signal-level indicator has no meaning with an NTP source.
    if configuration.timeSource == .msf {
      context.fillColor = displaySnapshot.signalHigh ? theme.indicatorHighColor : theme.indicatorLowColor
      if !context.fillRect(layoutMetrics.indicatorFrame) { return false }
    }

    guard drawSeconds(into: &context, clockSnapshot: snapshot, theme: theme) else { return false }

    guard drawClockTime(into: &context, clockSnapshot: snapshot, theme: theme) else { return false }

    guard drawClockDayOfWeek(into: &context, clockSnapshot: snapshot, theme: theme) else { return false }

    guard drawClockDate(into: &context, clockSnapshot: snapshot, theme: theme) else { return false }

    return true
  }
}

extension DigitalClockFace {
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

extension DigitalClockFace {
  func drawSeconds(into context: inout DrawingContext, clockSnapshot: ClockSnapshot, theme: Theme) -> Bool {
    let secondsFrame = layoutMetrics.secondsFrame
    let second = clockSnapshot.hasSecondTiming ? clockSnapshot.calendarDateTime.second : nil
    let color = theme.color(
      for: clockSnapshot.presentationState(
        for: clockSnapshot.clockState.minute,
        available: second != nil,
        policy: .clock
      )
    )

    var characters = InlineArray<2, UInt32>(repeating: 0)
    let unknown: UInt32 = 0x003F
    var output = characters.mutableSpan
    output[0] = second.map { UInt32(48 + $0 / 10) } ?? unknown
    output[1] = second.map { UInt32(48 + $0 % 10) } ?? unknown

    let advance = PixelOperator8Font.advance(of: characters.span)
    let xOffset = secondsFrame.maxX - advance - 1

    var pen = PixelPoint(x: xOffset, y: layoutMetrics.secondsBaseline)
    for index in characters.indices {
      guard let scalar = Unicode.Scalar(characters[index]),
        let glyph = PixelOperator8Font.glyph(for: scalar)
      else { return false }
      pen = context.drawGlyph(glyph, atPen: pen, color: color, clippedTo: secondsFrame)
    }

    // Draw the complete perimeter, even when second timing is unavailable.
    guard context.checkDeadline() else { return false }

    let inset = 1
    let width = layoutMetrics.panelSize.width - 2 * inset
    let height = layoutMetrics.panelSize.height - 2 * inset

    guard width > 1, height > 1 else { return true }

    let horizontal = width - 1
    let vertical = height - 1
    let perimeter = 2 * (horizontal + vertical)
    let dimBrightness: UInt32 = 64  // Approximately 25%

    func perimeterPoint(_ index: Int) -> PixelPoint {
      if index < horizontal {
        return PixelPoint(x: inset + index, y: inset)
      }
      if index < horizontal + vertical {
        return PixelPoint(
          x: inset + horizontal,
          y: inset + index - horizontal
        )
      }
      if index < 2 * horizontal + vertical {
        return PixelPoint(
          x: inset + horizontal - (index - horizontal - vertical),
          y: inset + vertical
        )
      }
      return PixelPoint(
        x: inset,
        y: inset + vertical - (index - 2 * horizontal - vertical)
      )
    }

    func scaledColor(_ brightness: UInt32) -> PixelColor32 {
      PixelColor32(
        red: color.red * brightness / 255,
        green: color.green * brightness / 255,
        blue: color.blue * brightness / 255
      )
    }

    // The deadline was checked above. Pixel writes do not check it again.
    // Permanent dim outline.
    let dimColor = scaledColor(dimBrightness)
    for index in 0..<perimeter {
      _ = context.setPixel(at: perimeterPoint(index), to: dimColor)
    }

    // Only illuminate progress when second timing is available.
    if let second, (0..<60).contains(second) {
      let elapsed =
        UInt64(second) * 1_000_000
        + UInt64(min(clockSnapshot.subsecondMicroseconds, 999_999))

      let scaled = elapsed * UInt64(perimeter)
      let fullPixels = Int(scaled / 60_000_000)
      let fraction = scaled % 60_000_000

      // Completed pixels at full brightness.
      for index in 0..<fullPixels {
        _ = context.setPixel(at: perimeterPoint(index), to: color)
      }

      // Fade the leading pixel from dim to full brightness.
      if fullPixels < perimeter {
        let brightness =
          dimBrightness
          + UInt32(
            fraction * UInt64(255 - dimBrightness) / 60_000_000
          )

        _ = context.setPixel(
          at: perimeterPoint(fullPixels),
          to: scaledColor(brightness)
        )
      }
    }
    return true
  }
}

extension DigitalClockFace {
  func drawClockTime(
    into context: inout DrawingContext,
    clockSnapshot: ClockSnapshot,
    theme: Theme
  ) -> Bool {
    let timeFrame = layoutMetrics.timeFrame

    var charValues: InlineArray<5, UInt32> = .init(repeating: 0)
    clockSnapshot.unicodeValuesFor24HourTime(policy: .clock, into: &charValues)

    // Centering the time string horizontally within the clock frame.
    let xOffset =
      timeFrame.minX + (timeFrame.width - ClockFont.advance(of: charValues.span)) / 2

    return clockSnapshot.draw24HourTime(
      charValues.span,
      into: &context,
      xOffset: xOffset,
      baselineY: layoutMetrics.timeBaseline,
      clippedTo: timeFrame,
      theme: theme,
      policy: .clock)
  }
}

extension DigitalClockFace {
  func drawClockDate(
    into context: inout DrawingContext,
    clockSnapshot: ClockSnapshot,
    theme: Theme
  ) -> Bool {
    var charValues: InlineArray<12, UInt32> = .init(repeating: 0)
    let charCount = clockSnapshot.unicodeValuesForDateMonthYear(
      policy: .clock,
      separator: 0x2E,
      numericMonth: true,
      into: &charValues)
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
      policy: .clock)
  }
}

extension DigitalClockFace {
  func drawClockDayOfWeek(
    into context: inout DrawingContext,
    clockSnapshot: ClockSnapshot,
    theme: Theme
  ) -> Bool {
    let availableWeekday = clockSnapshot.calendarDateTime.longDayOfWeek
    let state = clockSnapshot.presentationState(
      for: clockSnapshot.clockState.dayOfWeek,
      available: availableWeekday != nil,
      policy: .clock
    )

    let text: StaticString =
      state == .unknown ? "?" : (availableWeekday ?? "?")
    let frame = layoutMetrics.dayOfWeekFrame

    let xOffset =
      frame.minX + (frame.width - PixelOperator8Font.advance(of: text)) / 2

    _ = context.drawString(
      text,
      font: PixelOperator8Font.self,
      atPen: PixelPoint(x: xOffset, y: layoutMetrics.dayOfWeekBaseline),
      color: theme.color(for: state),
      clippedTo: frame
    )

    return context.canContinue
  }
}
