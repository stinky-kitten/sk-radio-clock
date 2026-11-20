//
//  NTPState.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-28.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct NTPReceipt {
  let instant: UTCInstant
  let receivedAt: UInt64

  static func publish(seconds: UInt32, fraction: UInt32, receivedAt: UInt64, into receipt: inout Self?) {
    // RFC 5905 reserves the all-zero wire timestamp for unknown time.
    guard seconds != 0 || fraction != 0 else { return }
    receipt = Self(
      instant: UTCInstant(
        unixSeconds: Int64(NTPState.unixSeconds(ntp: seconds)),
        nanoseconds: NTPState.nanoseconds(fromNTPFraction: fraction)
      ), receivedAt: receivedAt
    )
  }
}

// Absolute UTC samples and monotonic scheduling only; no software UTC clock.
struct NTPState {
  static let requestTimeoutUs: UInt64 = 30_000_000
  static let refreshUs: UInt64 = 3_600_000_000
  static let retryUs: UInt64 = 60_000_000
  private(set) var startedAt: UInt64?
  private(set) var lastSuccessUs: UInt64?
  private(set) var failed = false
  private(set) var nextAttemptUs: UInt64 = 0

  mutating func start(at now: UInt64) {
    startedAt = now
    failed = false
  }

  func accepts(instant: UTCInstant, receivedAt: UInt64) -> Bool {
    guard let startedAt, receivedAt >= startedAt,
      receivedAt - startedAt <= Self.requestTimeoutUs
    else { return false }

    return instant.unixSeconds >= 1_577_836_800
      && instant.unixSeconds < 4_102_444_800
      && instant.nanoseconds < 1_000_000_000
  }

  mutating func success(at now: UInt64) {
    lastSuccessUs = now
    startedAt = nil
    failed = false
    nextAttemptUs = Self.deadline(now, Self.refreshUs)
  }

  mutating func failure(at now: UInt64) {
    startedAt = nil
    failed = true
    nextAttemptUs = Self.deadline(now, Self.retryUs)
  }

  private static func deadline(_ now: UInt64, _ delay: UInt64) -> UInt64 {
    let (value, overflow) = now.addingReportingOverflow(delay)
    return overflow ? UInt64.max : value
  }

  // lwIP's signed era window spans 1968...2104. Accept only 2020...2099.
  static func unixSeconds(ntp: UInt32) -> UInt64 {
    ntp & 0x8000_0000 == 0 ? UInt64(ntp) + 2_085_978_496 : (ntp >= 2_208_988_800 ? UInt64(ntp) - 2_208_988_800 : 0)
  }

  static func validServerHeader(_ flags: UInt8, stratum: UInt8) -> Bool {
    let version = (flags >> 3) & 7
    // Stratum zero is left to SNTP's Kiss-of-Death handling.
    return flags >> 6 != 3 && (version == 3 || version == 4) && stratum <= 15
  }

  static func nanoseconds(fromNTPFraction fraction: UInt32) -> UInt32 {
    UInt32((UInt64(fraction) * 1_000_000_000) >> 32)
  }
}
