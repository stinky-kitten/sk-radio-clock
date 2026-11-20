//
//  MSFLogicalFrameTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-13.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

// Independent packed and transmitted forms of the archived 2026-09-29 17:42 fixture.
private let logicalFixtureA: UInt64 = 0x132_694b_c27e
private let logicalFixtureB: UInt64 = 0x6
private let logicalFixtureASequence = "0010011001001101001010010111100001001111110"
private let logicalFixtureBSequence = "0000000000000000000000000000000000000000110"

@Test("MSF logical frame requires 43 available positions", arguments: [0, 1, 41, 42])
func logicalFrameInsufficientConstruction(_ count: Int) {
  let completed = MSFCompletedFrame(
    aBits: logicalFixtureA, bBits: logicalFixtureB,
    dataCount: count, hasOpeningMarker: false)
  #expect(MSFLogicalFrame(completedFrame: completed) == nil)
  #expect(completed.logicalFrame() == nil)
}

@Test(
  "MSF logical frame construction uses the available suffix rather than minute-length policy",
  arguments: [43, 58, 59, 60, 65], [false, true])
func logicalFrameSufficientConstruction(_ count: Int, _ hasOpeningMarker: Bool) throws {
  let logical = try logicalFixture(dataCount: count, hasOpeningMarker: hasOpeningMarker)
  #expect(logical.hasUnknownPosition == false)
  #expect(logical.bits(atLogicalPosition: 17) == MSFBits(a: false, b: false))
  #expect(logical.bits(atLogicalPosition: 59) == MSFBits(a: false, b: false))
}

@Test(
  "MSF logical frame maps every fixture A/B pair for each physical minute length",
  arguments: [43, 58, 59, 60])
func logicalFrameFixtureMapping(_ count: Int) throws {
  let logical = try logicalFixture(dataCount: count)
  let expectedA = Array(logicalFixtureASequence.utf8)
  let expectedB = Array(logicalFixtureBSequence.utf8)
  #expect(expectedA.count == 43)
  #expect(expectedB.count == 43)
  for index in 0..<43 {
    let position = 17 + index
    let a = expectedA[index] == 49
    let b = expectedB[index] == 49
    #expect(logical.bits(atLogicalPosition: position) == MSFBits(a: a, b: b))
    #expect(logical.bit(at: position, channel: .a) == a)
    #expect(logical.bit(at: position, channel: .b) == b)
  }
}

@Test("MSF logical frame maps an isolated A or B bit at every position", arguments: 17...59)
func logicalFrameIsolatedChannelMapping(_ position: Int) throws {
  // Packed bit zero is logical position 59; expected positions are explicit,
  // without using the production index or mask helpers to construct the input.
  let mask = UInt64(1) << (59 - position)
  let aOnly = try logicalFixture(aBits: mask, bBits: 0)
  let bOnly = try logicalFixture(aBits: 0, bBits: mask)
  for observed in 17...59 {
    let selected = observed == position
    #expect(aOnly.bits(atLogicalPosition: observed) == MSFBits(a: selected, b: false))
    #expect(bOnly.bits(atLogicalPosition: observed) == MSFBits(a: false, b: selected))
    #expect(aOnly.bit(at: observed, channel: .a) == selected)
    #expect(aOnly.bit(at: observed, channel: .b) == false)
    #expect(bOnly.bit(at: observed, channel: .a) == false)
    #expect(bOnly.bit(at: observed, channel: .b) == selected)
  }
}

@Test("MSF logical position indices cover exactly zero through 42", arguments: 17...59)
func logicalFramePositionIndices(_ position: Int) {
  #expect(MSFLogicalFrame.index(forLogicalPosition: position) == position - 17)
}

@Test(
  "MSF logical lookups reject positions outside the suffix",
  arguments: [Int.min, -1, 0, 16, 60, 61, Int.max])
func logicalFrameOutOfRangeLookup(_ position: Int) throws {
  let logical = try logicalFixture()
  #expect(MSFLogicalFrame.index(forLogicalPosition: position) == nil)
  #expect(logical.bits(atLogicalPosition: position) == nil)
  #expect(logical.bit(at: position, channel: .a) == nil)
  #expect(logical.bit(at: position, channel: .b) == nil)
}

@Test(
  "MSF logical unknown positions remove both channels without shifting neighbours",
  arguments: 17...59)
func logicalFrameUnknownPropagation(_ position: Int) throws {
  let logical = try logicalFixture(unknownBits: UInt64(1) << (59 - position))
  let expectedA = Array(logicalFixtureASequence.utf8)
  let expectedB = Array(logicalFixtureBSequence.utf8)
  #expect(logical.hasUnknownPosition)
  for observed in 17...59 {
    if observed == position {
      #expect(logical.bits(atLogicalPosition: observed) == nil)
      #expect(logical.bit(at: observed, channel: .a) == nil)
      #expect(logical.bit(at: observed, channel: .b) == nil)
    } else {
      let index = observed - 17
      #expect(
        logical.bits(atLogicalPosition: observed)
          == MSFBits(
            a: expectedA[index] == 49, b: expectedB[index] == 49))
    }
  }
}

@Test("MSF logical frame retains every position when the whole suffix is unknown")
func logicalFrameAllUnknown() throws {
  let logical = try logicalFixture(unknownBits: 0x7ff_ffff_ffff)
  #expect(logical.hasUnknownPosition)
  for position in 17...59 {
    #expect(logical.bits(atLogicalPosition: position) == nil)
    #expect(logical.bit(at: position, channel: .a) == nil)
    #expect(logical.bit(at: position, channel: .b) == nil)
  }
  expectStructure(
    logical, year: .indeterminate, monthDay: .indeterminate,
    weekday: .indeterminate, hourMinute: .indeterminate, identifier: .indeterminate)
}

@Test("MSF logical construction ignores all packed bits outside the suffix")
func logicalFramePrefixIgnored() throws {
  let prefix = UInt64.max ^ UInt64(0x7ff_ffff_ffff)
  let logical = try logicalFixture(
    aBits: logicalFixtureA | prefix, bBits: logicalFixtureB | prefix, unknownBits: prefix)
  let expectedA = Array(logicalFixtureASequence.utf8)
  let expectedB = Array(logicalFixtureBSequence.utf8)
  #expect(logical.hasUnknownPosition == false)
  for position in 17...59 {
    let index = position - 17
    #expect(
      logical.bits(atLogicalPosition: position)
        == MSFBits(
          a: expectedA[index] == 49, b: expectedB[index] == 49))
  }
  expectStructure(logical)
}

@Test(
  "MSF logical packed masks select exact valid ranges",
  arguments: [
    (17...17, UInt64(0x400_0000_0000)),
    (59...59, UInt64(0x1)),
    (17...59, UInt64(0x7ff_ffff_ffff)),
    (17...24, UInt64(0x7f8_0000_0000)),
    (25...35, UInt64(0x7_ff00_0000)),
    (36...38, UInt64(0xe00000)),
    (39...51, UInt64(0x1fff00)),
    (52...59, UInt64(0xff)),
    (29...30, UInt64(0x6000_0000)),
    (30...30, UInt64(0x2000_0000)),
  ])
func logicalFramePackedMasks(_ positions: ClosedRange<Int>, _ expected: UInt64) {
  let mask = MSFLogicalFrame.packedMask(for: positions)
  #expect(mask == expected)
  #expect(mask.nonzeroBitCount == positions.count)
}

@Test(
  "MSF logical BCD fields match the independent fixture",
  arguments: [
    (MSFField.year, UInt8(26)), (.month, 9), (.dayOfMonth, 29),
    (.dayOfWeek, 2), (.hour, 17), (.minute, 42),
  ])
func logicalFrameFixtureBCD(_ field: MSFField, _ expected: UInt8) throws {
  #expect(try logicalFixture().bcdValue(for: field) == expected)
  // BCD uses A data; changing every B bit does not change the numeric fields.
  #expect(try logicalFixture(bBits: UInt64.max).bcdValue(for: field) == expected)
}

@Test(
  "MSF logical year BCD handles zero, digit transitions and two full digits",
  arguments: [
    (UInt64(0x00), UInt8(0)), (0x09, 9), (0x10, 10),
    (0x19, 19), (0x20, 20), (0x90, 90), (0x99, 99),
  ])
func logicalFrameYearBCDTransitions(_ encoded: UInt64, _ expected: UInt8) throws {
  let logical = try logicalFixture(aBits: encoded << 35, bBits: 0)
  #expect(logical.bcdValue(for: .year) == expected)
}

@Test(
  "MSF logical BCD conversion is independent of calendar ranges",
  arguments: [
    (MSFField.month, UInt64(0x19), 30, UInt8(19)),
    (.dayOfMonth, 0x39, 24, 39), (.dayOfWeek, 7, 21, 7),
    (.hour, 0x39, 15, 39), (.minute, 0x79, 8, 79),
  ])
func logicalFrameBCDOutsideCalendarRanges(
  _ field: MSFField, _ encoded: UInt64, _ shift: Int, _ expected: UInt8
) throws {
  #expect(try logicalFixture(aBits: encoded << shift, bBits: 0).bcdValue(for: field) == expected)
}

@Test(
  "MSF logical BCD rejects malformed ones or tens digits",
  arguments: [
    (MSFField.year, UInt64(0x2a), 35), (.year, 0xa6, 35), (.year, 0xff, 35),
    (.month, 0x0a, 30), (.dayOfMonth, 0x2a, 24),
    (.hour, 0x1f, 15), (.minute, 0x5a, 8),
  ])
func logicalFrameMalformedBCD(_ field: MSFField, _ encoded: UInt64, _ shift: Int) throws {
  #expect(try logicalFixture(aBits: encoded << shift, bBits: 0).bcdValue(for: field) == nil)
}

@Test(
  "MSF logical BCD rejects any unknown bit within its field",
  arguments: [
    (MSFField.year, 17...24), (.month, 25...29), (.dayOfMonth, 30...35),
    (.dayOfWeek, 36...38), (.hour, 39...44), (.minute, 45...51),
  ])
func logicalFrameUnknownBCD(_ field: MSFField, _ positions: ClosedRange<Int>) throws {
  for position in positions {
    let logical = try logicalFixture(unknownBits: UInt64(1) << (59 - position))
    #expect(logical.bcdValue(for: field) == nil)
  }
}

@Test(
  "MSF logical BCD remains known when an unrelated position is unknown",
  arguments: [
    (MSFField.year, UInt8(26)), (.month, 9), (.dayOfMonth, 29),
    (.dayOfWeek, 2), (.hour, 17), (.minute, 42),
  ])
func logicalFrameBCDWithUnrelatedUnknown(_ field: MSFField, _ expected: UInt8) throws {
  #expect(try logicalFixture(unknownBits: 1).bcdValue(for: field) == expected)
}

@Test("MSF structural analysis accepts all five checks in the known fixture")
func logicalFrameValidStructure() throws {
  expectStructure(try logicalFixture())
}

@Test(
  "MSF year structural check is independent",
  arguments: [
    (UInt64(1) << 42, UInt64(0), UInt64(0), MSFStructureResult.invalid),
    (0, 1 << 5, 0, .invalid),
    (0, 0, 1 << 42, .indeterminate), (0, 0, 1 << 35, .indeterminate),
  ])
func logicalFrameYearStructure(
  _ aFlip: UInt64, _ bFlip: UInt64, _ unknown: UInt64, _ expected: MSFStructureResult
) throws {
  expectStructure(
    try logicalFixture(
      aBits: logicalFixtureA ^ aFlip, bBits: logicalFixtureB ^ bFlip, unknownBits: unknown),
    year: expected)
}

@Test(
  "MSF month/day structural check is independent",
  arguments: [
    (UInt64(1) << 34, UInt64(0), UInt64(0), MSFStructureResult.invalid),
    (0, 1 << 4, 0, .invalid),
    (0, 0, 1 << 34, .indeterminate), (0, 0, 1 << 24, .indeterminate),
  ])
func logicalFrameMonthDayStructure(
  _ aFlip: UInt64, _ bFlip: UInt64, _ unknown: UInt64, _ expected: MSFStructureResult
) throws {
  expectStructure(
    try logicalFixture(
      aBits: logicalFixtureA ^ aFlip, bBits: logicalFixtureB ^ bFlip, unknownBits: unknown),
    monthDay: expected)
}

@Test(
  "MSF weekday structural check is independent",
  arguments: [
    (UInt64(1) << 23, UInt64(0), UInt64(0), MSFStructureResult.invalid),
    (0, 1 << 3, 0, .invalid),
    (0, 0, 1 << 23, .indeterminate), (0, 0, 1 << 21, .indeterminate),
  ])
func logicalFrameWeekdayStructure(
  _ aFlip: UInt64, _ bFlip: UInt64, _ unknown: UInt64, _ expected: MSFStructureResult
) throws {
  expectStructure(
    try logicalFixture(
      aBits: logicalFixtureA ^ aFlip, bBits: logicalFixtureB ^ bFlip, unknownBits: unknown),
    weekday: expected)
}

@Test(
  "MSF hour/minute structural check is independent",
  arguments: [
    (UInt64(1) << 20, UInt64(0), UInt64(0), MSFStructureResult.invalid),
    (0, 1 << 2, 0, .invalid),
    (0, 0, 1 << 20, .indeterminate), (0, 0, 1 << 8, .indeterminate),
  ])
func logicalFrameHourMinuteStructure(
  _ aFlip: UInt64, _ bFlip: UInt64, _ unknown: UInt64, _ expected: MSFStructureResult
) throws {
  expectStructure(
    try logicalFixture(
      aBits: logicalFixtureA ^ aFlip, bBits: logicalFixtureB ^ bFlip, unknownBits: unknown),
    hourMinute: expected)
}

@Test("MSF identifier checks every fixed A bit independently", arguments: 0...7)
func logicalFrameIdentifierInvalid(_ offset: Int) throws {
  expectStructure(
    try logicalFixture(aBits: logicalFixtureA ^ (UInt64(1) << offset)), identifier: .invalid)
}

@Test("MSF identifier is indeterminate for unknown non-parity positions", arguments: [0, 1, 6, 7])
func logicalFrameIdentifierUnknown(_ offset: Int) throws {
  expectStructure(
    try logicalFixture(unknownBits: UInt64(1) << offset), identifier: .indeterminate)
}

@Test(
  "MSF unknown parity positions also make the identifier indeterminate",
  arguments: [
    (
      5, MSFStructureResult.indeterminate, MSFStructureResult.valid,
      MSFStructureResult.valid, MSFStructureResult.valid
    ),
    (4, .valid, .indeterminate, .valid, .valid),
    (3, .valid, .valid, .indeterminate, .valid),
    (2, .valid, .valid, .valid, .indeterminate),
  ])
func logicalFrameUnknownParityPosition(
  _ offset: Int, _ year: MSFStructureResult, _ monthDay: MSFStructureResult,
  _ weekday: MSFStructureResult, _ hourMinute: MSFStructureResult
) throws {
  expectStructure(
    try logicalFixture(unknownBits: UInt64(1) << offset),
    year: year, monthDay: monthDay, weekday: weekday, hourMinute: hourMinute,
    identifier: .indeterminate)
}

@Test("MSF partial analysis retains both invalid and valid determinable checks")
func logicalFrameMixedPartialStructure() throws {
  expectStructure(
    try logicalFixture(bBits: logicalFixtureB ^ (1 << 4), unknownBits: 1 << 42),
    year: .indeterminate, monthDay: .invalid)
}

@Test("MSF multiple unknown groups do not hide the remaining structural results")
func logicalFrameMultipleUnknownGroups() throws {
  expectStructure(
    try logicalFixture(unknownBits: (1 << 42) | (1 << 20)),
    year: .indeterminate, hourMinute: .indeterminate)
}

@Test(
  "MSF identifier unknown data takes precedence over a known mismatch",
  arguments: [
    (7, 0), (0, 7),
  ])
func logicalFrameIdentifierMismatchAndUnknown(_ mismatch: Int, _ unknown: Int) throws {
  expectStructure(
    try logicalFixture(
      aBits: logicalFixtureA ^ (UInt64(1) << mismatch), unknownBits: UInt64(1) << unknown),
    identifier: .indeterminate)
}

@Test("MSF structural analysis ignores B bits outside its four parity positions")
func logicalFrameUnprotectedBStructure() throws {
  expectStructure(try logicalFixture(bBits: logicalFixtureB ^ 0x7ff_ffff_ffc3))
}

private func logicalFixture(
  aBits: UInt64 = logicalFixtureA, bBits: UInt64 = logicalFixtureB,
  unknownBits: UInt64 = 0, dataCount: Int = 43, hasOpeningMarker: Bool = false
) throws -> MSFLogicalFrame {
  let completed = MSFCompletedFrame(
    aBits: aBits, bBits: bBits, unknownBits: unknownBits,
    dataCount: dataCount, hasOpeningMarker: hasOpeningMarker)
  return try #require(MSFLogicalFrame(completedFrame: completed))
}

private func expectStructure(
  _ logical: MSFLogicalFrame, year: MSFStructureResult = .valid,
  monthDay: MSFStructureResult = .valid, weekday: MSFStructureResult = .valid,
  hourMinute: MSFStructureResult = .valid, identifier: MSFStructureResult = .valid
) {
  let result = logical.analyze()
  #expect(result.yearParity == year)
  #expect(result.monthDayParity == monthDay)
  #expect(result.dayOfWeekParity == weekday)
  #expect(result.hourMinuteParity == hourMinute)
  #expect(result.fixedIdentifier == identifier)
}
