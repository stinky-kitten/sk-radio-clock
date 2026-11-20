//
//  AnalyticalClockFace+Theme.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-20.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension AnalyticalClockFace {
  struct Theme: ClockTheme, EpistemicPalette, TimeTextTheme {
    let backgroundColor: PixelColor32
    let traceBackgroundColor: PixelColor32

    let indicatorHighColor: PixelColor32
    let indicatorLowColor: PixelColor32
    let pulseColor: PixelColor32
    let bitsColor: PixelColor32

    let unknownColor: PixelColor32
    let candidateColor: PixelColor32
    let supportedColor: PixelColor32
    let confirmedColor: PixelColor32
    let timeSeparatorColor: PixelColor32

    func color(for state: EpistemicState) -> PixelColor32 {
      switch state {
      case .unknown:
        return unknownColor
      case .candidate:
        return candidateColor
      case .supported:
        return supportedColor
      case .confirmed:
        return confirmedColor
      }
    }
  }
}

extension AnalyticalClockFace.Theme {
  static let standard = AnalyticalClockFace.Theme(
    backgroundColor: .black,
    traceBackgroundColor: .darkGreen,
    indicatorHighColor: .green,
    indicatorLowColor: .darkGreen,
    pulseColor: .green,
    bitsColor: .green,

    unknownColor: .red,
    candidateColor: .orange,
    supportedColor: .amber,
    confirmedColor: .purple,
    timeSeparatorColor: .gray
  )
}
