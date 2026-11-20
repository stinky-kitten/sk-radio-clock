//
//  MSFDiagnosticsTransportTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-20.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import MSFDiagnosticsTransport
import Testing

// This is the sole test owner of the real C transport. The scanner suite uses
// separate Swift capture, so the two suites can run independently.
@Suite("MSF diagnostics transport", .serialized)
struct MSFDiagnosticsTransportTests {
  init() {
    emptyTransport()
  }

  @Test("Diagnostic FIFO starts observably empty with no drops")
  func emptyFIFO() {
    defer { emptyTransport() }
    var record = MSFDiagnostic()
    #expect(!msf_diagnostics_pop(&record))
    #expect(msf_diagnostics_take_dropped() == 0)
  }

  @Test(
    "Diagnostic FIFO preserves every field including independent flags and integer boundaries",
    arguments: Array(UInt8(0)...7), [Int32.min, -12_454, 0, Int32.max])
  func diagnosticPayload(_ flags: UInt8, _ phaseError: Int32) {
    defer { emptyTransport() }
    let expected = MSFDiagnostic(
      since_previous: UInt64.max, since_second: 0x8000_0000_0000_0000,
      scan_index: UInt32.max, phase_error_us: phaseError,
      state: 251, reset_reason: 252, scan_event: 253, phase_step: 254,
      missing_slots: 255, rising: flags & 1 != 0,
      has_previous: flags & 2 != 0, has_second: flags & 4 != 0)
    enqueueDiagnostic(expected)
    var actual = MSFDiagnostic()
    #expect(msf_diagnostics_pop(&actual))
    expectDiagnostic(actual, expected)
    #expect(!msf_diagnostics_pop(&actual))
    #expect(msf_diagnostics_take_dropped() == 0)
  }

  @Test("Diagnostic FIFO returns multiple records in insertion order")
  func fifoOrder() {
    defer { emptyTransport() }
    let expected = [diagnostic(index: 11), diagnostic(index: 22), diagnostic(index: 33)]
    for record in expected { enqueueDiagnostic(record) }
    var actual = MSFDiagnostic()
    for record in expected {
      #expect(msf_diagnostics_pop(&actual))
      expectDiagnostic(actual, record)
    }
    #expect(!msf_diagnostics_pop(&actual))
  }

  @Test("Diagnostic FIFO accepts exactly sixty-four records without dropping any")
  func fifoCapacity() {
    defer { emptyTransport() }
    #expect(MSF_DIAGNOSTIC_CAPACITY == 64)
    for index in UInt32(0)..<64 { enqueueDiagnostic(diagnostic(index: index)) }
    #expect(msf_diagnostics_take_dropped() == 0)
    var actual = MSFDiagnostic()
    for index in UInt32(0)..<64 {
      #expect(msf_diagnostics_pop(&actual))
      expectDiagnostic(actual, diagnostic(index: index))
    }
    #expect(!msf_diagnostics_pop(&actual))
  }

  @Test(
    "Excess diagnostic enqueues count exact drops and preserve all oldest records",
    arguments: [1, 3, 9])
  func fifoFullDrops(_ excess: Int) {
    defer { emptyTransport() }
    for index in UInt32(203)..<267 { enqueueDiagnostic(diagnostic(index: index)) }
    for _ in 0..<excess { enqueueDiagnostic(diagnostic(index: 999)) }
    // The archived fixture did not directly assert its three rejected records.
    #expect(msf_diagnostics_take_dropped() == UInt32(excess))
    #expect(msf_diagnostics_take_dropped() == 0)
    var actual = MSFDiagnostic()
    for index in UInt32(203)..<267 {
      #expect(msf_diagnostics_pop(&actual))
      expectDiagnostic(actual, diagnostic(index: index))
    }
    #expect(!msf_diagnostics_pop(&actual))
  }

  @Test("Freeing one FIFO slot admits a new record behind the remaining old records")
  func fifoFreedSlot() {
    defer { emptyTransport() }
    for index in UInt32(0)..<64 { enqueueDiagnostic(diagnostic(index: index)) }
    enqueueDiagnostic(diagnostic(index: 999))
    var actual = MSFDiagnostic()
    #expect(msf_diagnostics_pop(&actual))
    expectDiagnostic(actual, diagnostic(index: 0))
    enqueueDiagnostic(diagnostic(index: 1000))
    for index in UInt32(1)..<64 {
      #expect(msf_diagnostics_pop(&actual))
      expectDiagnostic(actual, diagnostic(index: index))
    }
    #expect(msf_diagnostics_pop(&actual))
    expectDiagnostic(actual, diagnostic(index: 1000))
    #expect(!msf_diagnostics_pop(&actual))
    #expect(msf_diagnostics_take_dropped() == 1)
  }

  @Test("Taking diagnostic drops resets only the counter and does not release a full FIFO")
  func fifoDropReset() {
    defer { emptyTransport() }
    for index in UInt32(0)..<64 { enqueueDiagnostic(diagnostic(index: index)) }
    enqueueDiagnostic(diagnostic(index: 998))
    enqueueDiagnostic(diagnostic(index: 999))
    #expect(msf_diagnostics_take_dropped() == 2)
    #expect(msf_diagnostics_take_dropped() == 0)
    enqueueDiagnostic(diagnostic(index: 1000))
    #expect(msf_diagnostics_take_dropped() == 1)
    var actual = MSFDiagnostic()
    #expect(msf_diagnostics_pop(&actual))
    expectDiagnostic(actual, diagnostic(index: 0))
  }

  @Test("Diagnostic FIFO physically wraps while partially occupied without changing order")
  func fifoOccupiedWrap() {
    defer { emptyTransport() }
    for index in UInt32(0)..<48 { enqueueDiagnostic(diagnostic(index: index)) }
    var actual = MSFDiagnostic()
    for index in UInt32(0)..<32 {
      #expect(msf_diagnostics_pop(&actual))
      expectDiagnostic(actual, diagnostic(index: index))
    }
    for index in UInt32(48)..<96 { enqueueDiagnostic(diagnostic(index: index)) }
    for index in UInt32(32)..<96 {
      #expect(msf_diagnostics_pop(&actual))
      expectDiagnostic(actual, diagnostic(index: index))
    }
    #expect(!msf_diagnostics_pop(&actual))
    #expect(msf_diagnostics_take_dropped() == 0)
  }

  @Test("Repeated diagnostic enqueue and pop reuse every physical slot", arguments: [203, 1024])
  func fifoRepeatedReuse(_ count: Int) {
    defer { emptyTransport() }
    var actual = MSFDiagnostic()
    for index in 0..<count {
      let expected = diagnostic(index: UInt32(index))
      enqueueDiagnostic(expected)
      #expect(msf_diagnostics_pop(&actual))
      expectDiagnostic(actual, expected)
    }
    #expect(!msf_diagnostics_pop(&actual))
    #expect(msf_diagnostics_take_dropped() == 0)
  }

  @Test("An empty diagnostic pop leaves all destination fields unchanged")
  func fifoEmptyDestination() {
    defer { emptyTransport() }
    let expected = diagnostic(index: 123)
    var actual = expected
    #expect(!msf_diagnostics_pop(&actual))
    expectDiagnostic(actual, expected)
    enqueueDiagnostic(diagnostic(index: 456))
    #expect(msf_diagnostics_pop(&actual))
    expectDiagnostic(actual, diagnostic(index: 456))
    #expect(!msf_diagnostics_pop(&actual))
    expectDiagnostic(actual, diagnostic(index: 456))
  }

  @Test("A consumed diagnostic copy remains valid after its physical slot is reused")
  func fifoCopyOwnership() {
    defer { emptyTransport() }
    let expected = diagnostic(index: 123)
    enqueueDiagnostic(expected)
    var held = MSFDiagnostic()
    #expect(msf_diagnostics_pop(&held))
    var scratch = MSFDiagnostic()
    for index in UInt32(0)..<256 {
      enqueueDiagnostic(diagnostic(index: index))
      #expect(msf_diagnostics_pop(&scratch))
    }
    expectDiagnostic(held, expected)
    held.scan_index = 999
    enqueueDiagnostic(diagnostic(index: 321))
    #expect(msf_diagnostics_pop(&scratch))
    expectDiagnostic(scratch, diagnostic(index: 321))
  }

  @Test("Completed-frame mailbox starts observably empty with no frame drops")
  func emptyMailbox() {
    defer { emptyTransport() }
    var frame = MSFFrameRecord()
    #expect(!msf_frame_take(&frame))
    #expect(msf_frame_take_dropped() == 0)
  }

  @Test(
    "Completed-frame mailbox copies all fields including marker flags and numeric boundaries",
    arguments: [UInt32(0), 43, 58, 59, 60, UInt32.max], [false, true])
  func framePayload(_ count: UInt32, _ opening: Bool) {
    defer { emptyTransport() }
    let expected = MSFFrameRecord(
      a_bits: UInt64.max, b_bits: 0x8000_0000_0000_0000,
      unknown_bits: 0x1234_5678_9abc_def0, closing_marker_us: UInt64.max,
      data_count: count, has_opening_marker: opening)
    publishFrame(expected)
    var actual = MSFFrameRecord()
    #expect(msf_frame_take(&actual))
    expectFrame(actual, expected)
    #expect(!msf_frame_take(&actual))
    #expect(msf_frame_take_dropped() == 0)
  }

  @Test("An empty frame take preserves the complete destination before and after consumption")
  func mailboxEmptyDestination() {
    defer { emptyTransport() }
    let expected = archivedFrame()
    var actual = expected
    #expect(!msf_frame_take(&actual))
    expectFrame(actual, expected)
    publishFrame(expected)
    #expect(msf_frame_take(&actual))
    #expect(!msf_frame_take(&actual))
    expectFrame(actual, expected)
  }

  @Test(
    "A pending frame survives later publications and every rejection is counted",
    arguments: [1, 3, 9])
  func mailboxFullDrops(_ excess: Int) {
    defer { emptyTransport() }
    let first = archivedFrame()
    publishFrame(first)
    for _ in 0..<excess {
      publishFrame(
        MSFFrameRecord(
          a_bits: 0xffff, b_bits: 0xffff, unknown_bits: 0,
          closing_marker_us: 987_654_321, data_count: 60, has_opening_marker: true))
    }
    #expect(msf_frame_take_dropped() == UInt32(excess))
    #expect(msf_frame_take_dropped() == 0)
    var actual = MSFFrameRecord()
    #expect(msf_frame_take(&actual))
    expectFrame(actual, first)
    #expect(!msf_frame_take(&actual))
  }

  @Test("Taking frame drops neither consumes nor releases the pending mailbox")
  func mailboxDropReset() {
    defer { emptyTransport() }
    let first = archivedFrame()
    publishFrame(first)
    publishFrame(MSFFrameRecord())
    #expect(msf_frame_take_dropped() == 1)
    #expect(msf_frame_take_dropped() == 0)
    publishFrame(MSFFrameRecord())
    #expect(msf_frame_take_dropped() == 1)
    var actual = MSFFrameRecord()
    #expect(msf_frame_take(&actual))
    expectFrame(actual, first)
  }

  @Test("Consumed mailbox storage accepts a new frame and preserves its recorded timestamp")
  func mailboxReuse() {
    defer { emptyTransport() }
    var actual = MSFFrameRecord()
    publishFrame(archivedFrame())
    #expect(msf_frame_take(&actual))
    expectFrame(actual, archivedFrame())
    let second = MSFFrameRecord(
      a_bits: 1, b_bits: 2, unknown_bits: 0,
      closing_marker_us: 234_567_890, data_count: 58, has_opening_marker: true)
    publishFrame(second)
    #expect(msf_frame_take(&actual))
    expectFrame(actual, second)
    #expect(!msf_frame_take(&actual))
    #expect(msf_frame_take_dropped() == 0)
  }

  @Test("Repeated frame publication and consumption reuse the single mailbox", arguments: [3, 203])
  func mailboxRepeatedReuse(_ count: Int) {
    defer { emptyTransport() }
    var actual = MSFFrameRecord()
    for index in 0..<count {
      let expected = MSFFrameRecord(
        a_bits: UInt64(index), b_bits: 0x5678,
        unknown_bits: 0x40, closing_marker_us: 5_000_000_000 + UInt64(index),
        data_count: 59, has_opening_marker: true)
      publishFrame(expected)
      #expect(msf_frame_take(&actual))
      expectFrame(actual, expected)
      #expect(!msf_frame_take(&actual))
    }
    #expect(msf_frame_take_dropped() == 0)
  }

  @Test("Previously consumed frame copies survive storage reuse and cannot mutate the mailbox")
  func mailboxCopyOwnership() {
    defer { emptyTransport() }
    let first = archivedFrame()
    publishFrame(first)
    var held = MSFFrameRecord()
    #expect(msf_frame_take(&held))
    let second = MSFFrameRecord(
      a_bits: 1, b_bits: 2, unknown_bits: 0,
      closing_marker_us: 234_567_890, data_count: 58, has_opening_marker: true)
    publishFrame(second)
    expectFrame(held, first)
    held.a_bits = 999
    var actual = MSFFrameRecord()
    #expect(msf_frame_take(&actual))
    expectFrame(actual, second)
    #expect(held.a_bits == 999 && held.closing_marker_us == 123_456_789)
  }

  @Test("Markerless partial and unknown-bit frame payloads are transported without interpretation")
  func archivedPartialFrames() {
    defer { emptyTransport() }
    let expected = [
      MSFFrameRecord(
        a_bits: 0x132_694b_c27e, b_bits: 0x6, unknown_bits: 0,
        closing_marker_us: 345_678_901, data_count: 43, has_opening_marker: false),
      MSFFrameRecord(
        a_bits: 0, b_bits: 0, unknown_bits: 0x1000_0000,
        closing_marker_us: 456_789_012, data_count: 59, has_opening_marker: true),
    ]
    var actual = MSFFrameRecord()
    for frame in expected {
      publishFrame(frame)
      #expect(msf_frame_take(&actual))
      expectFrame(actual, frame)
    }
  }

  @Test(
    "Unknown masks preserve high bits and overlap with known A and B payloads",
    arguments: [UInt64(0), 1, 0x1000_0000, 0x8000_0000_0000_0000, UInt64.max])
  func unknownMasks(_ unknown: UInt64) {
    defer { emptyTransport() }
    let expected = MSFFrameRecord(
      a_bits: UInt64.max, b_bits: UInt64.max,
      unknown_bits: unknown, closing_marker_us: 5_000_000_000,
      data_count: 43, has_opening_marker: false)
    publishFrame(expected)
    var actual = MSFFrameRecord()
    #expect(msf_frame_take(&actual))
    expectFrame(actual, expected)
  }

  @Test("FIFO and mailbox capacities, payloads and dropped counters remain independent")
  func independentTransports() {
    defer { emptyTransport() }
    for index in UInt32(0)..<64 { enqueueDiagnostic(diagnostic(index: index)) }
    enqueueDiagnostic(diagnostic(index: 999))
    let frame = archivedFrame()
    publishFrame(frame)  // A full FIFO does not prevent mailbox publication.
    publishFrame(MSFFrameRecord())
    publishFrame(MSFFrameRecord())
    #expect(msf_diagnostics_take_dropped() == 1)
    #expect(msf_frame_take_dropped() == 2)
    #expect(msf_diagnostics_take_dropped() == 0)
    #expect(msf_frame_take_dropped() == 0)
    var record = MSFDiagnostic()
    #expect(msf_diagnostics_pop(&record))
    expectDiagnostic(record, diagnostic(index: 0))
    enqueueDiagnostic(diagnostic(index: 1000))  // A full mailbox does not block enqueue.
    for index in UInt32(1)..<64 {
      #expect(msf_diagnostics_pop(&record))
      expectDiagnostic(record, diagnostic(index: index))
    }
    #expect(msf_diagnostics_pop(&record))
    expectDiagnostic(record, diagnostic(index: 1000))
    var actual = MSFFrameRecord()
    #expect(msf_frame_take(&actual))
    expectFrame(actual, frame)
    #expect(!msf_diagnostics_pop(&record))
    #expect(!msf_frame_take(&actual))
  }
}

private func emptyTransport() {
  var diagnostic = MSFDiagnostic()
  while msf_diagnostics_pop(&diagnostic) {}
  var frame = MSFFrameRecord()
  _ = msf_frame_take(&frame)
  _ = msf_diagnostics_take_dropped()
  _ = msf_frame_take_dropped()
}

private func diagnostic(index: UInt32) -> MSFDiagnostic {
  MSFDiagnostic(
    since_previous: 10, since_second: 20, scan_index: index,
    phase_error_us: -12_454, state: 1, reset_reason: 0, scan_event: 4,
    phase_step: 3, missing_slots: 2, rising: true, has_previous: true, has_second: true)
}

private func enqueueDiagnostic(_ record: MSFDiagnostic) {
  msf_diagnostics_enqueue(
    record.rising, record.state, record.has_previous,
    record.since_previous, record.has_second, record.since_second, record.scan_index,
    record.reset_reason, record.scan_event, record.phase_step,
    record.missing_slots, record.phase_error_us)
}

private func expectDiagnostic(_ actual: MSFDiagnostic, _ expected: MSFDiagnostic) {
  #expect(actual.since_previous == expected.since_previous)
  #expect(actual.since_second == expected.since_second)
  #expect(actual.scan_index == expected.scan_index)
  #expect(actual.phase_error_us == expected.phase_error_us)
  #expect(actual.state == expected.state)
  #expect(actual.reset_reason == expected.reset_reason)
  #expect(actual.scan_event == expected.scan_event)
  #expect(actual.phase_step == expected.phase_step)
  #expect(actual.missing_slots == expected.missing_slots)
  #expect(actual.rising == expected.rising)
  #expect(actual.has_previous == expected.has_previous)
  #expect(actual.has_second == expected.has_second)
}

private func archivedFrame() -> MSFFrameRecord {
  MSFFrameRecord(
    a_bits: 0x1234, b_bits: 0x5678, unknown_bits: 0x40,
    closing_marker_us: 123_456_789, data_count: 59, has_opening_marker: true)
}

private func publishFrame(_ frame: MSFFrameRecord) {
  msf_frame_publish(
    frame.a_bits, frame.b_bits, frame.unknown_bits,
    frame.data_count, frame.has_opening_marker, frame.closing_marker_us)
}

private func expectFrame(_ actual: MSFFrameRecord, _ expected: MSFFrameRecord) {
  #expect(actual.a_bits == expected.a_bits)
  #expect(actual.b_bits == expected.b_bits)
  #expect(actual.unknown_bits == expected.unknown_bits)
  #expect(actual.closing_marker_us == expected.closing_marker_us)
  #expect(actual.data_count == expected.data_count)
  #expect(actual.has_opening_marker == expected.has_opening_marker)
}
