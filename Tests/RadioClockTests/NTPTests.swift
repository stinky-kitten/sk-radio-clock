//
//  NTPTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-28.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

#if canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

@Test("NTP clock snapshots convert UTC across both 2026 UK clock changes")
func ntpSnapshotUKClockChanges() throws {
  // libc's time zone is process-wide. Keep all four cases in one test and
  // restore the previous setting, including when a requirement fails.
  let previousTZ = getenv("TZ").map { String(cString: $0) }
  defer {
    if let previousTZ {
      #expect(setenv("TZ", previousTZ, 1) == 0)
    } else {
      #expect(unsetenv("TZ") == 0)
    }
    tzset()
  }
  let uk = TimeZoneConfiguration.uk
  try #require(uk.makeCurrent())

  // Both changes occur at 01:00 UTC. Check the seconds immediately around each.
  let cases: [(unixSeconds: Int64, local: CalendarDateTimeComponents)] = [
    (
      1_774_745_999,
      .init(
        year: 2026, month: 3, dayOfMonth: 29, dayOfWeek: 0, hour: 0, minute: 59, second: 59, timeZone: .gmt)
    ),
    (
      1_774_746_000,
      .init(
        year: 2026, month: 3, dayOfMonth: 29, dayOfWeek: 0, hour: 2, minute: 0, second: 0, timeZone: .bst)
    ),
    (
      1_792_889_999,
      .init(
        year: 2026, month: 10, dayOfMonth: 25, dayOfWeek: 0, hour: 1, minute: 59, second: 59, timeZone: .bst)
    ),
    (
      1_792_890_000,
      .init(
        year: 2026, month: 10, dayOfMonth: 25, dayOfWeek: 0, hour: 1, minute: 0, second: 0, timeZone: .gmt)
    ),
  ]
  for (unixSeconds, local) in cases {
    let instant = UTCInstant(unixSeconds: unixSeconds, nanoseconds: 0)
    let snapshot = try #require(ClockSnapshot(instant: instant, timeZone: uk))
    #expect(snapshot.calendarDateTime == local)
    #expect(snapshot.hasAcquiredTime && snapshot.hasSecondTiming)
  }
}

@Test func ntpZeroTimestampDoesNotPublishOrReplaceAReceipt() throws {
  var state = NTPState()
  state.start(at: 1_000)
  var pending: NTPReceipt?

  NTPReceipt.publish(seconds: 0, fraction: 0, receivedAt: 2_000, into: &pending)
  #expect(pending == nil)

  NTPReceipt.publish(seconds: 4_008_988_800, fraction: 0, receivedAt: 2_000, into: &pending)
  let valid = try #require(pending)
  #expect(valid.instant.unixSeconds == 1_800_000_000)
  #expect(valid.instant.nanoseconds == 0)
  #expect(state.accepts(instant: valid.instant, receivedAt: valid.receivedAt))

  NTPReceipt.publish(seconds: 0, fraction: 0, receivedAt: 3_000, into: &pending)
  #expect(pending?.instant.unixSeconds == valid.instant.unixSeconds)
  #expect(pending?.instant.nanoseconds == valid.instant.nanoseconds)
  #expect(pending?.receivedAt == valid.receivedAt)

  state.success(at: valid.receivedAt)
  state.start(at: state.nextAttemptUs)
  pending = nil
  NTPReceipt.publish(seconds: 0, fraction: 0, receivedAt: state.nextAttemptUs, into: &pending)
  #expect(pending == nil)
  #expect(state.lastSuccessUs == valid.receivedAt)
}

@Test(arguments: [(UInt32(1), UInt32(0)), (0x8000_0000, 500_000_000)])
func ntpRolloverTimestampStillUsesRequestWindow(fraction: UInt32, nanoseconds: UInt32) throws {
  var pending: NTPReceipt?
  NTPReceipt.publish(seconds: 0, fraction: fraction, receivedAt: 2_000, into: &pending)
  let sample = try #require(pending)
  #expect(sample.instant.unixSeconds == 2_085_978_496)
  #expect(sample.instant.nanoseconds == nanoseconds)

  var state = NTPState()
  #expect(!state.accepts(instant: sample.instant, receivedAt: sample.receivedAt))
  state.start(at: 1_000)
  #expect(state.accepts(instant: sample.instant, receivedAt: sample.receivedAt))
  #expect(!state.accepts(instant: sample.instant, receivedAt: 1_001 + NTPState.requestTimeoutUs))
}

@Test func ntpValidityAndRecovery() {
  var state = NTPState()
  let valid = UTCInstant(unixSeconds: 1_800_000_000, nanoseconds: 0)

  #expect(state.lastSuccessUs == nil)
  #expect(!state.accepts(instant: valid, receivedAt: 0))

  state.start(at: 1_000)
  #expect(!state.accepts(instant: valid, receivedAt: 999))
  #expect(!state.accepts(instant: valid, receivedAt: 30_001_001))

  let fractional = UTCInstant(
    unixSeconds: 1_800_000_000,
    nanoseconds: 999_999_999
  )
  #expect(state.accepts(instant: fractional, receivedAt: 2_000))

  state.success(at: 2_000)
  #expect(state.lastSuccessUs == 2_000)

  state.start(at: state.nextAttemptUs)
  state.failure(at: 4_000_000_000)
  #expect(state.failed)
  #expect(state.lastSuccessUs == 2_000)

  state.start(at: state.nextAttemptUs)
  state.success(at: 4_100_000_000)
  #expect(!state.failed)
  #expect(state.lastSuccessUs == 4_100_000_000)
}

@Test func ntpBoundaries() {
  #expect(NTPState.unixSeconds(ntp: UInt32.max) == 2_085_978_495)
  #expect(NTPState.unixSeconds(ntp: 0) == 2_085_978_496)
  #expect(NTPState.unixSeconds(ntp: 0x8000_0000) == 0)
  #expect(
    NTPState.nanoseconds(fromNTPFraction: UInt32.max) == 999_999_999
  )

  var state = NTPState()
  state.start(at: 0)

  for seconds: Int64 in [
    Int64.min,
    0,
    1_577_836_799,
    4_102_444_800,
    Int64.max,
  ] {
    #expect(
      !state.accepts(
        instant: UTCInstant(unixSeconds: seconds, nanoseconds: 0),
        receivedAt: 1
      ))
  }

  #expect(
    !state.accepts(
      instant: UTCInstant(
        unixSeconds: 1_800_000_000,
        nanoseconds: 1_000_000_000
      ),
      receivedAt: 1
    ))
}

@Test func ntpSchedulingOverflow() {
  var state = NTPState()
  state.failure(at: UInt64.max - 1)
  #expect(state.nextAttemptUs == UInt64.max)

  state.success(at: UInt64.max - 1)
  #expect(state.nextAttemptUs == UInt64.max)
}

@Test func ntpServerQuality() {
  #expect(NTPState.validServerHeader(0x24, stratum: 2))
  #expect(!NTPState.validServerHeader(0xe4, stratum: 2))
  #expect(!NTPState.validServerHeader(0x24, stratum: 16))
  #expect(!NTPState.validServerHeader(0x14, stratum: 2))
}
