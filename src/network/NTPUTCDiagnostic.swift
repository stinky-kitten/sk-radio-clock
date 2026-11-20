//
//  NTPUTCDiagnostic.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-28.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// Diagnostic-only UTC formatting. No application calendar model or timezone state.
#if SWIFT_PACKAGE
  #if canImport(Darwin)
    import Darwin
  #else
    import Glibc
  #endif
#endif

struct NTPUTCDiagnostic {
  let bytes: InlineArray<24, UInt8>

  // Four-digit ISO years, Unix epoch through 9999. Exact time_t conversion also
  // rejects values outside the target C library's range rather than narrowing.
  static func make(seconds: Int64, nanoseconds: Int64) -> Self? {
    guard seconds >= 0, seconds <= 253_402_300_799,
      var unix = time_t(exactly: seconds), nanoseconds >= 0, nanoseconds < 1_000_000_000
    else { return nil }
    var calendar = tm()
    guard gmtime_r(&unix, &calendar) != nil else { return nil }
    return format(calendar: calendar, nanoseconds: nanoseconds)
  }

  // Optional conversion result allows explicit failure-path verification.
  static func format(calendar: tm?, nanoseconds: Int64) -> Self? {
    guard let calendar, calendar.tm_year >= 70, calendar.tm_year <= 8099,
      (0...11).contains(calendar.tm_mon), (1...31).contains(calendar.tm_mday),
      (0...23).contains(calendar.tm_hour), (0...59).contains(calendar.tm_min),
      (0...60).contains(calendar.tm_sec), nanoseconds >= 0, nanoseconds < 1_000_000_000
    else { return nil }
    var bytes: InlineArray<24, UInt8> = .init(repeating: 48)
    bytes[4] = 45
    bytes[7] = 45
    bytes[10] = 84
    bytes[13] = 58
    bytes[16] = 58
    bytes[19] = 46
    bytes[23] = 90
    func digits(_ value: Int, at offset: Int, count: Int) {
      var value = value
      for index in (offset..<(offset + count)).reversed() {
        bytes[index] = UInt8(value % 10) + 48
        value /= 10
      }
    }
    digits(Int(calendar.tm_year) + 1900, at: 0, count: 4)
    digits(Int(calendar.tm_mon) + 1, at: 5, count: 2)
    digits(Int(calendar.tm_mday), at: 8, count: 2)
    digits(Int(calendar.tm_hour), at: 11, count: 2)
    digits(Int(calendar.tm_min), at: 14, count: 2)
    digits(Int(calendar.tm_sec), at: 17, count: 2)
    digits(Int(nanoseconds / 1_000_000), at: 20, count: 3)
    return Self(bytes: bytes)
  }
}
