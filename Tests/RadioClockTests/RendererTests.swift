//
//  RendererTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import SKLSHUB75
import Testing

@testable import RadioClockLogic

@Test("Renderer skips a nil framebuffer without reading time or invoking the actual face")
func rendererNilFramebuffer() {
  var request = wrapperRequest(framebuffer: nil, deadline: 10_100_000)
  let renderer = Renderer(
    clockFace: AnalyticalClockFace(
      layoutMetrics: .init(size: PixelSize(width: 64, height: 64)),
      configuration: .init(timeSource: .msf, theme: .standard, timeZone: .uk), theme: wrapperTheme))
  // Any attempted face checkpoint exhausts this empty script immediately.
  // A nil request with otherwise valid dimensions cannot construct/access a
  // usable framebuffer, so returning safely verifies the guard as well.
  RenderHostTime.withTimestamps([]) {
    #expect(!renderer.render(&request, displaySnapshot: wrapperSnapshot()))
    #expect(RenderHostTime.readCount == 0)
  }
  #expect(request.framebuffer == nil)
  #expect(request.width == 64 && request.height == 64)
}

@Test("Renderer forwards a valid guarded framebuffer snapshot and future deadline to the configured face")
func rendererValidRequest() {
  let pixels = wrapperBuffer { framebuffer in
    var request = wrapperRequest(framebuffer: framebuffer.baseAddress, deadline: 10_100_000)
    let originalPointer = request.framebuffer
    let renderer = Renderer(
      clockFace: AnalyticalClockFace(
        layoutMetrics: .init(size: PixelSize(width: 64, height: 64)),
        configuration: .init(timeSource: .msf, theme: .standard, timeZone: .uk), theme: wrapperTheme))
    // 64 clear rows + 4 indicator rows + (7 trace rows + 3 strokes)
    // + (8 bit rows + 6 glyphs) + 5 time + 10 date + 3 timezone glyphs.
    RenderHostTime.withTimestamps(Array(repeating: 10_000_000, count: 110)) {
      #expect(renderer.render(&request, displaySnapshot: wrapperSnapshot()))
      #expect(RenderHostTime.readCount == 110)
    }
    #expect(request.framebuffer == originalPointer)
    #expect(request.width == 64 && request.height == 64 && request.deadline_us == 10_100_000)
  }
  // Literal representative references; extensive face/glyph rasters are
  // covered elsewhere. These colours deliberately differ from .standard.
  #expect(pixels[2 * 64 + 58] == 0xff00_00ff)  // supplied raw LOW and low-indicator tint
  #expect(pixels[14 * 64 + 2] == 0xffff_ff00)  // supplied LOW trace bin
  #expect(pixels[11 * 64 + 3] == 0xffff_ff00)  // transition to supplied HIGH bin
  #expect(pixels[11 * 64 + 4] == 0xff80_0080)  // trace background
  #expect(pixels[18 * 64 + 4] == 0xff00_ffff)  // supplied marker and bit tint
  #expect(pixels[27 * 64 + 9] == 0xffff_00ff)  // 17, supported hour
  #expect(pixels[27 * 64 + 42] == 0xffff_6000)  // 42, candidate minute
  #expect(pixels[30 * 64 + 30] == 0xff80_8080)  // neutral separator
  #expect(pixels[50 * 64 + 44] == 0xffff_ffff)  // opaque year ink
  #expect(pixels[25 * 64] == 0xff20_2020)  // supplied main background
  #expect(pixels[0] == 0xff20_2020)
  #expect(pixels[24 * 64 + 32] == 0xff20_2020)
}

@Test(
  "Renderer forwards deadline equality and expiration so the first face checkpoint leaves all storage untouched",
  arguments: [UInt64(10_100_000), 10_100_001])
func rendererExpiredDeadline(_ now: UInt64) {
  let pixels = wrapperBuffer { framebuffer in
    var request = wrapperRequest(framebuffer: framebuffer.baseAddress, deadline: 10_100_000)
    let renderer = Renderer(
      clockFace: AnalyticalClockFace(
        layoutMetrics: .init(size: PixelSize(width: 64, height: 64)),
        configuration: .init(timeSource: .msf, theme: .standard, timeZone: .uk), theme: wrapperTheme))
    // Exactly one read is allowed. Any later stage would exhaust the script.
    RenderHostTime.withTimestamps([now]) {
      #expect(!renderer.render(&request, displaySnapshot: wrapperSnapshot()))
      #expect(RenderHostTime.readCount == 1)
    }
  }
  #expect(pixels.allSatisfy { $0 == wrapperSentinel })
}

@Test("Renderer returns false after partial rendering and preserves the cancelled stages")
func rendererPartialCancellation() {
  let pixels = wrapperBuffer { framebuffer in
    var request = wrapperRequest(framebuffer: framebuffer.baseAddress, deadline: 10_100_000)
    let renderer = Renderer(
      clockFace: AnalyticalClockFace(
        layoutMetrics: .init(size: PixelSize(width: 64, height: 64)),
        configuration: .init(timeSource: .msf, theme: .standard, timeZone: .uk), theme: wrapperTheme))
    RenderHostTime.withTimestamps(Array(repeating: 10_000_000, count: 68) + [10_100_000]) {
      #expect(!renderer.render(&request, displaySnapshot: wrapperSnapshot()))
      #expect(RenderHostTime.readCount == 69)
    }
  }
  #expect(pixels[2 * 64 + 58] == 0xff00_00ff)
  #expect(pixels[14 * 64 + 2] == 0xff20_2020)
  #expect(pixels[27 * 64 + 9] == 0xff20_2020)
}

private let wrapperSentinel: UInt32 = 0x1234_5678
private let wrapperTheme = AnalyticalClockFace.Theme(
  backgroundColor: .darkGray, traceBackgroundColor: .purple,
  indicatorHighColor: .red, indicatorLowColor: .blue, pulseColor: .yellow, bitsColor: .cyan,
  unknownColor: .red, candidateColor: .orange, supportedColor: .magenta,
  confirmedColor: .white, timeSeparatorColor: .gray)

private func wrapperSnapshot() -> MSFDisplaySnapshot {
  let clock = ClockSnapshot(
    calendarDateTime: CalendarDateTimeComponents(
      year: 2026, month: 9, dayOfMonth: 29, dayOfWeek: 2, hour: 17, minute: 42,
      second: 0, timeZone: .bst),
    clockState: ClockState(
      year: .confirmed, month: .confirmed, dayOfMonth: .confirmed, dayOfWeek: .confirmed,
      hour: .supported, minute: .candidate, timeZone: .confirmed))
  return MSFDisplaySnapshot(
    clockSnapshot: clock, secondPhaseBin: 0,
    timestamp: 10_000_000, signalHigh: false, highBins: 2, lowBins: 1,
    seconds: [.decoded(.minuteMarker), .absent, .absent, .absent, .absent, .absent])
}

private func wrapperRequest(
  framebuffer: UnsafeMutablePointer<UInt32>?, deadline: UInt64
)
  -> HUB75RenderRequest
{
  HUB75RenderRequest(
    generation: 7, framebuffer: framebuffer, width: 64, height: 64,
    presentation_time_us: 10_001_000, deadline_us: deadline)
}

private func wrapperBuffer(_ render: (UnsafeMutableBufferPointer<UInt32>) -> Void) -> [UInt32] {
  let prefix: [UInt32] = [0xdead_beef, 0xcafe_babe, 0x1122_3344, 0x5566_7788]
  let suffix: [UInt32] = [0x99aa_bbcc, 0xddee_ff00, 0xface_feed, 0xbaad_f00d]
  var storage = prefix + Array(repeating: wrapperSentinel, count: 4096) + suffix
  storage.withUnsafeMutableBufferPointer { buffer in
    render(UnsafeMutableBufferPointer(start: buffer.baseAddress!.advanced(by: 4), count: 4096))
  }
  #expect(Array(storage.prefix(4)) == prefix)
  #expect(Array(storage.suffix(4)) == suffix)
  return Array(storage[4..<4100])
}

extension AnalyticalClockFace {
  fileprivate init(size: PixelSize, theme: Theme) {
    self.init(
      layoutMetrics: LayoutMetrics(size: size),
      configuration: ClockConfiguration(
        timeSource: .msf,
        theme: .standard,
        timeZone: .uk
      ),
      theme: theme
    )
  }
}

@Test("Renderer rejects an expired context even when the face returns true")
func rendererChecksContextStatus() {
  let pixels = wrapperBuffer { buffer in
    var request = wrapperRequest(framebuffer: buffer.baseAddress, deadline: 100)
    RenderHostTime.withTimestamps([100]) {
      #expect(!Renderer(clockFace: StatusProbeFace()).render(&request, displaySnapshot: wrapperSnapshot()))
      #expect(RenderHostTime.readCount == 1)
    }
  }
  #expect(pixels.allSatisfy { $0 == wrapperSentinel })
}

private struct StatusProbeFace: ClockFace {
  func render(into context: inout DrawingContext, displaySnapshot: MSFDisplaySnapshot) -> Bool {
    _ = context.checkDeadline()
    return true
  }
}
