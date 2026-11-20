//
//  NTPUTCDiagnosticTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-28.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

private func utc(_ seconds: Int64, _ nanos: Int64 = 0) -> String? {
  guard let formatted = NTPUTCDiagnostic.make(seconds: seconds, nanoseconds: nanos) else { return nil }
  return String(decoding: (0..<24).map { formatted.bytes[$0] }, as: UTF8.self)
}

@Test func utcKnownDates() {
  #expect(utc(1_793_216_087, 59_000_000) == "2026-10-28T19:34:47.059Z")
  #expect(utc(0) == "1970-01-01T00:00:00.000Z")
  #expect(utc(951_782_400) == "2000-02-29T00:00:00.000Z")
  #expect(utc(1_709_164_799, 999_999_999) == "2024-02-28T23:59:59.999Z")
  #expect(utc(1_709_164_800) == "2024-02-29T00:00:00.000Z")
  #expect(utc(1_709_251_200) == "2024-03-01T00:00:00.000Z")
  #expect(utc(1_735_689_599) == "2024-12-31T23:59:59.000Z")
  #expect(utc(1_735_689_600) == "2025-01-01T00:00:00.000Z")
  #expect(utc(2_147_483_647) == "2038-01-19T03:14:07.000Z")
  #expect(utc(2_147_483_648) == "2038-01-19T03:14:08.000Z")
  #expect(utc(253_402_300_799) == "9999-12-31T23:59:59.000Z")
}

@Test func utcFractionsAndFailure() {
  #expect(utc(0, 59_999_999) == "1970-01-01T00:00:00.059Z")
  #expect(utc(0, 1_000_000) == "1970-01-01T00:00:00.001Z")
  #expect(utc(0, 999_999) == "1970-01-01T00:00:00.000Z")
  for seconds: Int64 in [-1, Int64.min, Int64.max, 253_402_300_800] { #expect(utc(seconds) == nil) }
  #expect(utc(0, -1) == nil)
  #expect(utc(0, 1_000_000_000) == nil)
  #expect(NTPUTCDiagnostic.format(calendar: nil, nanoseconds: 0) == nil)
}
