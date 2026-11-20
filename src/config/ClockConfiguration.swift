//
//  ClockConfiguration.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-29.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

enum ClockThemeKind {
  case standard
}

struct ClockConfiguration {
  let timeSource: TimeSource
  let theme: ClockThemeKind
  let timeZone: TimeZoneConfiguration
  let ntpServer: StaticString?

  init(timeSource: TimeSource, theme: ClockThemeKind, timeZone: TimeZoneConfiguration, ntpServer: StaticString? = nil) {
    self.timeSource = timeSource
    self.theme = theme
    self.timeZone = timeZone
    self.ntpServer = ntpServer
  }
}
