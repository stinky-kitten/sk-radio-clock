//
//  ClockTheme.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-11-03.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

protocol ClockTheme {
  static var standard: Self { get }
  var backgroundColor: PixelColor32 { get }
}

protocol EpistemicPalette {
  func color(for state: EpistemicState) -> PixelColor32
}

protocol TimeTextTheme {
  var timeSeparatorColor: PixelColor32 { get }
}
