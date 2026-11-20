//
//  MSFTraceRenderingTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

private let traceSentinel: UInt32 = 0x1234_5678
private let traceAllBins: UInt64 = 0x0fff_ffff_ffff_ffff

@Test("MSF component geometry uses the firmware panel and current trace bit and clock relationships")
func traceRenderingGeometry() {
  let layout = AnalyticalClockFace.LayoutMetrics(size: PixelSize(width: 64, height: 64))
  #expect(layout.panelSize == PixelSize(width: 64, height: 64))
  #expect(layout.traceFrame == PixelRect(x: 2, y: 8, width: 60, height: 7))
  #expect(layout.bitsFrame == PixelRect(x: 2, y: 15, width: 60, height: 8))
  #expect(layout.clockFrame == PixelRect(x: 0, y: 25, width: 64, height: 22))
  #expect(layout.traceFrame.maxY == layout.bitsFrame.minY)
  #expect(layout.bitsFrame.maxY + 2 == layout.clockFrame.minY)
  #expect(AnalyticalClockFace.LayoutMetrics.bitSlotCount == 6)
  #expect(AnalyticalClockFace.LayoutMetrics.bitSlotWidth == 10)
}

@Test("MSF standard trace and bit theme colours are opaque green over dark green")
func traceRenderingTheme() {
  let theme = AnalyticalClockFace.Theme.standard
  #expect(theme.traceBackgroundColor.alpha == 255 && theme.traceBackgroundColor.xrgb8888 == 0xff00_0f00)
  #expect(theme.pulseColor.alpha == 255 && theme.pulseColor.xrgb8888 == 0xff00_ff00)
  #expect(theme.bitsColor.alpha == 255 && theme.bitsColor.xrgb8888 == 0xff00_ff00)
}

@Test("MSF unknown trace clears all sixty columns without touching any other display region")
func traceRenderingUnknown() {
  let pixels = tracePixels(traceSnapshot(high: 0, low: 0))
  expectTracePixels(pixels) { _, _ in false }
}

@Test("MSF trace steady LOW and HIGH draw complete inclusive baselines", arguments: [false, true])
func traceRenderingBaselines(_ high: Bool) {
  let pixels = tracePixels(traceSnapshot(high: high ? traceAllBins : 0, low: high ? 0 : traceAllBins))
  expectTracePixels(pixels) { x, y in (2..<62).contains(x) && y == (high ? 8 : 14) }
}

@Test(
  "MSF every logical trace bin maps to its physical column with independent LOW and HIGH flags",
  arguments: 0..<60, [(false, true), (true, false), (true, true)] as [(Bool, Bool)])
func traceRenderingColumnMapping(_ bin: Int, _ levels: (Bool, Bool)) {
  let (high, low) = levels
  let mask = UInt64(1) << bin
  let pixels = tracePixels(traceSnapshot(high: high ? mask : 0, low: low ? mask : 0))
  // The independent reference grid has oldest x=2, newest x=61,
  // HIGH y=8 and LOW y=14; a mixed interval spans all seven rows.
  expectTracePixels(pixels) { x, y in
    x == 2 + bin && (high && low ? (8..<15).contains(y) : y == (high ? 8 : 14))
  }
}

@Test("MSF trace adjacent definite levels join vertically at the newer column", arguments: [false, true])
func traceRenderingJoins(_ firstHigh: Bool) {
  let pixels = tracePixels(traceSnapshot(high: firstHigh ? 1 : 2, low: firstHigh ? 2 : 1))
  expectTracePixels(pixels) { x, y in
    (x == 2 && y == (firstHigh ? 8 : 14)) || (x == 3 && (8..<15).contains(y))
  }
}

@Test("MSF unknown trace bins break runs instead of drawing across missing history", arguments: [false, true])
func traceRenderingUnknownBreak(_ afterHigh: Bool) {
  let pixels = tracePixels(traceSnapshot(high: afterHigh ? 4 : 0, low: afterHigh ? 1 : 5))
  expectTracePixels(pixels) { x, y in
    (x == 2 && y == 14) || (x == 4 && y == (afterHigh ? 8 : 14))
  }
}

@Test(
  "MSF mixed trace intervals draw vertical activity and restart later definite runs",
  arguments: [false, true], [false, true])
func traceRenderingMixedBreak(_ beforeHigh: Bool, _ afterHigh: Bool) {
  let high: UInt64 = 2 | (beforeHigh ? 1 : 0) | (afterHigh ? 4 : 0)
  let low: UInt64 = 2 | (beforeHigh ? 0 : 1) | (afterHigh ? 0 : 4)
  let pixels = tracePixels(traceSnapshot(high: high, low: low))
  expectTracePixels(pixels) { x, y in
    (x == 2 && y == (beforeHigh ? 8 : 14)) || (x == 3 && (8..<15).contains(y))
      || (x == 4 && y == (afterHigh ? 8 : 14))
  }
}

@Test("MSF dense mixed activity fills all trace columns and preserves both side margins")
func traceRenderingDense() {
  let pixels = tracePixels(traceSnapshot(high: traceAllBins, low: traceAllBins))
  expectTracePixels(pixels) { x, y in (2..<62).contains(x) && (8..<15).contains(y) }
}

@Test("MSF trace ignores packed flags beyond its sixty-column history")
func traceRenderingUnusedBits() {
  let pixels = tracePixels(traceSnapshot(high: 0xf000_0000_0000_0000, low: 0xf000_0000_0000_0000))
  expectTracePixels(pixels) { _, _ in false }
}

@Test("MSF trace clears earlier waveform pixels when a later snapshot has no activity")
func traceRenderingClearsPrevious() {
  let pixels = traceBuffer { context in
    let face = AnalyticalClockFace(
      size: PixelSize(width: 64, height: 64),
      configuration: ClockConfiguration(timeSource: .msf, theme: .standard, timeZone: .uk)
    )
    face.drawTrace(
      into: &context, displaySnapshot: traceSnapshot(high: traceAllBins, low: traceAllBins),
      theme: .standard)
    face.drawTrace(
      into: &context, displaySnapshot: traceSnapshot(high: 0, low: 0),
      theme: .standard)
  }
  expectTracePixels(pixels) { _, _ in false }
}

@Test("MSF scanner raw pulse snapshot renders the newest mixed interval and its steady LOW history")
func traceRenderingScannerPulse() {
  // Raw observation does not call the shared scanner output recorder.
  var scan = MSFScan()
  scan.observeRawSignal(high: false, at: 0)
  scan.observeRawSignal(high: true, at: 5_905_000)
  scan.observeRawSignal(high: false, at: 5_905_001)
  let snapshot = scan.displaySnapshot(at: 6_000_000)
  #expect(snapshot.highBins == 0x0800_0000_0000_0000 && snapshot.lowBins == traceAllBins)
  let pixels = tracePixels(snapshot)
  expectTracePixels(pixels) { x, y in
    ((2..<62).contains(x) && y == 14) || (x == 61 && (8..<15).contains(y))
  }
}

private func traceSnapshot(high: UInt64, low: UInt64) -> MSFDisplaySnapshot {
  MSFDisplaySnapshot(
    clockSnapshot: .unknown, secondPhaseBin: nil, timestamp: 6_000_000,
    signalHigh: false, highBins: high, lowBins: low)
}

private func tracePixels(_ snapshot: MSFDisplaySnapshot) -> [UInt32] {
  traceBuffer { context in
    AnalyticalClockFace(
      size: PixelSize(width: 64, height: 64),
      configuration: ClockConfiguration(timeSource: .msf, theme: .standard, timeZone: .uk)
    ).drawTrace(
      into: &context, displaySnapshot: snapshot, theme: .standard)
  }
}

private func traceBuffer(_ draw: (inout DrawingContext) -> Void) -> [UInt32] {
  let prefix: [UInt32] = [0xdead_beef, 0xcafe_babe, 0x1122_3344, 0x5566_7788]
  let suffix: [UInt32] = [0x99aa_bbcc, 0xddee_ff00, 0xface_feed, 0xbaad_f00d]
  var storage = prefix + Array(repeating: traceSentinel, count: 4096) + suffix
  storage.withUnsafeMutableBufferPointer { buffer in
    var context = DrawingContext(
      framebuffer: UnsafeMutableBufferPointer(
        start: buffer.baseAddress!.advanced(by: 4), count: 4096), contextSize: PixelSize(width: 64, height: 64),
      pixelFormat: .bgrx8888)!
    draw(&context)
  }
  #expect(Array(storage.prefix(4)) == prefix && Array(storage.suffix(4)) == suffix)
  return Array(storage[4..<4100])
}

// Expected geometry is literal firmware-panel coordinates, not a second
// waveform algorithm. Every pixel outside the component must retain its marker.
private func expectTracePixels(_ pixels: [UInt32], ink: (Int, Int) -> Bool) {
  for y in 0..<64 {
    for x in 0..<64 {
      let inTrace = (2..<62).contains(x) && (8..<15).contains(y)
      let expected: UInt32 = inTrace ? (ink(x, y) ? 0xff00_ff00 : 0xff00_0f00) : traceSentinel
      #expect(pixels[y * 64 + x] == expected)
    }
  }
}
