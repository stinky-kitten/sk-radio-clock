//
//  HUB75.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-16.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import SKLSHUB75

struct HUB75 {
  let panelSize: PixelSize

  init(panelSize: PixelSize) {
    self.panelSize = panelSize
  }

  func start() -> Bool {
    // Configure, initialise, launch Core 1,
    // and wait for the driver to become ready.

    var hardware = HUB75HardwareDescriptor(
      width: UInt16(panelSize.width),
      height: UInt16(panelSize.height)
    )

    var configuration = HUB75Configuration()
    var resolutionPolicy = HUB75ResolutionPolicy()
    configuration.apply6Bit4Phase240HzPreset(resolutionPolicy: &resolutionPolicy)

    let result = initializeHUB75(
      hardware: &hardware,
      configuration: &configuration,
      resolutionPolicy: &resolutionPolicy
    )
    if result != .ok {
      return false
    }

    multicore_launch_core1(runHUB75Core1)

    let deadline = time_us_64() + 5 * 1000 * 1000
    while time_us_64() < deadline {
      var status = HUB75Status()
      if readHUB75Status(into: &status) {
        if status.lifecycle_state == .running {
          return status.target_result != .failed
        }
        if status.lifecycle_state == .failed {
          return false
        }
      }
      sleep_us(1000)
    }
    return false
  }
}
