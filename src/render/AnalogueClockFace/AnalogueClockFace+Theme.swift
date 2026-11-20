//
//  AnalogueClockFace+Theme.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-20.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension AnalogueClockFace {
  struct Theme: ClockTheme {
    let backgroundColor: PixelColor32
    let faceColor: PixelColor32
    let bezelColor: PixelColor32
    let markerColor: PixelColor32

    let hourHandColor: PixelColor32
    let minuteHandColor: PixelColor32
    let secondHandColor: PixelColor32
    let centreBossColor: PixelColor32

    let indicatorHighColor: PixelColor32
    let indicatorLowColor: PixelColor32
  }
}

extension AnalogueClockFace.Theme {
  static let standard = AnalogueClockFace.Theme(
    backgroundColor: .black,
    faceColor: .white,
    bezelColor: .gray,
    markerColor: .gray,
    hourHandColor: .black,
    minuteHandColor: .black,
    secondHandColor: .red,
    centreBossColor: .black,
    indicatorHighColor: .green,
    indicatorLowColor: .darkGreen
  )
}
