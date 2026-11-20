//
//  AnalogueClockFace.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-20.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct AnalogueClockFace: ClockFace {

  private let configuration: ClockConfiguration
  let layoutMetrics: LayoutMetrics
  let theme: Theme

  init(size: PixelSize, configuration: ClockConfiguration) {
    // The panel is at most 64 columns wide.
    precondition(size.width <= 64)
    self.layoutMetrics = LayoutMetrics(size: size)
    self.configuration = configuration
    switch configuration.theme {
    case .standard:
      self.theme = .standard
    }
  }

  private func drawDial(into context: inout DrawingContext, coverageRow: inout MutableSpan<UInt8>) -> Bool {
    let centre = layoutMetrics.centre
    context.fillColor = theme.bezelColor
    guard context.fillAntialiasedCircle(centre: centre, radius: layoutMetrics.dialRadius, coverageRow: &coverageRow)
    else { return false }

    context.fillColor = theme.faceColor
    guard context.fillAntialiasedCircle(centre: centre, radius: layoutMetrics.faceRadius, coverageRow: &coverageRow)
    else { return false }

    context.fillColor = theme.markerColor
    for marker in 0..<12 {
      let major = marker % 3 == 0
      let geometry = layoutMetrics.radialRectangle(
        angle: Float(marker) * (.tau / 12),
        innerRadius: major ? layoutMetrics.majorMarkerInnerRadius : layoutMetrics.minorMarkerInnerRadius,
        outerRadius: layoutMetrics.markerOuterRadius,
        width: major ? layoutMetrics.majorMarkerWidth : layoutMetrics.minorMarkerWidth
      )
      guard context.fillAntialiasedQuad(geometry, coverageRow: &coverageRow) else { return false }
    }
    return true
  }

  func render(
    into drawingContext: inout DrawingContext,
    displaySnapshot: MSFDisplaySnapshot
  ) -> Bool {
    guard drawingContext.contextSize == layoutMetrics.panelSize else { return false }

    var row = InlineArray<64, UInt8>(repeating: 0)
    var scratch = row.mutableSpan

    drawingContext.fillColor = theme.backgroundColor
    guard drawingContext.fillRect(drawingContext.contextFrame), drawDial(into: &drawingContext, coverageRow: &scratch)
    else { return false }

    let angles = HandAngles(snapshot: displaySnapshot.clockSnapshot)
    if let hour = angles.hour {
      drawingContext.fillColor = theme.hourHandColor
      let geometry = layoutMetrics.radialRectangle(angle: hour, dimensions: layoutMetrics.hourHand)
      guard drawingContext.fillAntialiasedQuad(geometry, coverageRow: &scratch) else { return false }
    }

    if let minute = angles.minute {
      drawingContext.fillColor = theme.minuteHandColor
      let geometry = layoutMetrics.radialRectangle(angle: minute, dimensions: layoutMetrics.minuteHand)
      guard drawingContext.fillAntialiasedQuad(geometry, coverageRow: &scratch) else { return false }
    }

    if let second = angles.second {
      drawingContext.fillColor = theme.secondHandColor
      let geometry = layoutMetrics.radialRectangle(angle: second, dimensions: layoutMetrics.secondHand)
      guard drawingContext.fillAntialiasedQuad(geometry, coverageRow: &scratch) else { return false }
    }

    if angles.hour != nil || angles.minute != nil || angles.second != nil {
      drawingContext.fillColor = theme.centreBossColor
      guard
        drawingContext.fillAntialiasedCircle(
          centre: layoutMetrics.centre, radius: layoutMetrics.centreBossRadius, coverageRow: &scratch)
      else { return false }
    }

    if configuration.timeSource == .msf {
      drawingContext.fillColor = displaySnapshot.signalHigh ? theme.indicatorHighColor : theme.indicatorLowColor
      return drawingContext.fillRect(layoutMetrics.indicatorFrame)
    }
    return true
  }
}

extension AnalogueClockFace {
  struct HandAngles {
    let hour: Float?
    let minute: Float?
    let second: Float?

    init(snapshot: ClockSnapshot) {
      let time = snapshot.calendarDateTime

      let seconds: Float? =
        snapshot.hasSecondTiming
        ? time.second.map { Float($0) + Float(snapshot.subsecondMicroseconds) / 1_000_000 } : nil

      let minutes: Float? =
        snapshot.hasMinute
        ? time.minute.map { Float($0) + (seconds ?? 0) / 60 } : nil

      second = seconds.map { $0 * (.tau / 60) }
      minute = minutes.map { $0 * (.tau / 60) }

      hour =
        snapshot.hasHour
        ? time.hour.map { (Float($0 % 12) + (minutes ?? 0) / 60) * (.tau / 12) } : nil
    }
  }
}
