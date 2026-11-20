//
//  TimeSource.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-28.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// The sole application-level choice of time acquisition subsystem.
enum TimeSource: Equatable {
  case msf
  #if SK_RADIO_CLOCK_NO_WIFI
    @available(*, unavailable, message: "NTP selection requires pico2_w with SK_RADIO_CLOCK_WIFI=ON")
  #endif
  case ntp
}
