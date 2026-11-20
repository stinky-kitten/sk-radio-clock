//
//  TimeZoneConfiguration.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-30.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

#if SWIFT_PACKAGE
  #if canImport(Darwin)
    import Darwin
  #else
    import Glibc
  #endif
#endif

struct TimeZoneConfiguration {
  // Literal rules avoid an allocating Swift String-to-C conversion at startup.
  let posixTZ: StaticString
  let standard: TimeZone
  let daylight: TimeZone?

  func makeCurrent() -> Bool {
    guard setenv("TZ", UnsafeRawPointer(posixTZ.utf8Start).assumingMemoryBound(to: CChar.self), 1) == 0 else {
      return false
    }
    tzset()
    return true
  }
}

extension TimeZoneConfiguration {
  static let uk = Self(
    posixTZ: "GMT0BST,M3.5.0/1,M10.5.0/2",
    standard: .gmt,
    daylight: .bst
  )
}
