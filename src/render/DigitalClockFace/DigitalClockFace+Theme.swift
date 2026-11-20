//
//  DigitalClockFace+Theme.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-30.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension DigitalClockFace {
  struct Theme: ClockTheme, EpistemicPalette, TimeTextTheme {
    let backgroundColor: PixelColor32

    let indicatorHighColor: PixelColor32
    let indicatorLowColor: PixelColor32

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

extension DigitalClockFace.Theme {
  static let standard = DigitalClockFace.Theme(
    backgroundColor: .black,
    indicatorHighColor: .green,
    indicatorLowColor: .darkGreen,

    unknownColor: .red,
    candidateColor: .orange,
    supportedColor: .purple,
    confirmedColor: .purple,
    timeSeparatorColor: .gray
  )
}
