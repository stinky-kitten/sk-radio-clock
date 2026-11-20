//
//  AnalogueClockFaceTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-20.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import AppKit
import Foundation
import SKLSHUB75
import Testing

@testable import RadioClockLogic

private let analogueSentinel: UInt32 = 0x1234_5678

@Test(
  "Analogue hand angles include subsecond, minute and hour contributions",
  arguments: [
    (12, 0, 0, UInt32(0), Float(0), Float(0), Float(0)),
    (3, 15, 30, 0, 97.75, 93, 180),
    (0, 0, 0, 500_000, 1.0 / 240, 0.05, 3),
    (23, 59, 59, 500_000, 359.995833, 359.95, 357),
  ] as [(Int, Int, Int, UInt32, Float, Float, Float)])
func analogueAngles(
  _ hour: Int, _ minute: Int, _ second: Int, _ microseconds: UInt32,
  _ hourDegrees: Float, _ minuteDegrees: Float, _ secondDegrees: Float
) throws {
  let angles = AnalogueClockFace.HandAngles(
    snapshot: analogueSnapshot(hour, minute, second, microseconds).clockSnapshot)
  #expect(abs((try #require(angles.hour)) * 180 / .pi - hourDegrees) < 0.0001)
  #expect(abs((try #require(angles.minute)) * 180 / .pi - minuteDegrees) < 0.0001)
  #expect(abs((try #require(angles.second)) * 180 / .pi - secondDegrees) < 0.0001)
}

@Test("Minute, hour and midnight transitions retain continuous hand geometry", arguments: [0, 11, 23])
func analogueTransitions(_ hour: Int) throws {
  let before = AnalogueClockFace.HandAngles(snapshot: analogueSnapshot(hour, 59, 59, 999_000).clockSnapshot)
  let after = AnalogueClockFace.HandAngles(snapshot: analogueSnapshot((hour + 1) % 24, 0, 0).clockSnapshot)
  let layout = AnalogueClockFace.LayoutMetrics(size: PixelSize(width: 64, height: 64))
  for (a, b) in [(before.hour, after.hour), (before.minute, after.minute), (before.second, after.second)] {
    let beforeQuad = layout.radialRectangle(
      angle: try #require(a), innerRadius: -2, outerRadius: 26, width: 1)
    let afterQuad = layout.radialRectangle(
      angle: try #require(b), innerRadius: -2, outerRadius: 26, width: 1)
    for vertex in 0..<4 {
      #expect(abs(beforeQuad.vertices[vertex].x - afterQuad.vertices[vertex].x) < 0.004)
      #expect(abs(beforeQuad.vertices[vertex].y - afterQuad.vertices[vertex].y) < 0.004)
    }
  }
}

@Test("Radial geometry preserves fractional centre, width and length", arguments: [Float(0), .pi / 2, .pi, .pi * 1.5])
func analogueGeometry(_ angle: Float) {
  let layout = AnalogueClockFace.LayoutMetrics(size: PixelSize(width: 64, height: 64))
  let quad = layout.radialRectangle(angle: angle, innerRadius: -2, outerRadius: 16, width: 3.75)
  let vertices = quad.vertices
  let startX = (vertices[0].x + vertices[3].x) / 2
  let startY = (vertices[0].y + vertices[3].y) / 2
  let endX = (vertices[1].x + vertices[2].x) / 2
  let endY = (vertices[1].y + vertices[2].y) / 2
  #expect(abs(hypotf(endX - startX, endY - startY) - 18) < 0.00001)
  #expect(abs(hypotf(vertices[0].x - vertices[3].x, vertices[0].y - vertices[3].y) - 3.75) < 0.00001)
  #expect(abs((startX * 8 + endX) / 9 - 32) < 0.00001)
  #expect(abs((startY * 8 + endY) / 9 - 32) < 0.00001)
  #expect(layout.centre == DrawingPoint(x: 32, y: 32))
}

@Test("Twelve o'clock composition has symmetric dial, markers, black hands, red second and black boss")
func analogueNoon() {
  let pixels = renderAnalogue(analogueSnapshot(12, 0, 0))
  #expect(pixels[0] == PixelColor32.black.xrgb8888)
  #expect(pixels[2 * 64 + 31] == PixelColor32.white.xrgb8888)
  #expect(pixels[0 * 64 + 31] != PixelColor32.white.xrgb8888)  // bezel
  #expect(pixels[4 * 64 + 31] == PixelColor32.gray.xrgb8888)  // 12 marker
  #expect(pixels[31 * 64 + 4] == PixelColor32.gray.xrgb8888)  // 9 marker
  #expect(pixels[31 * 64 + 59] == PixelColor32.gray.xrgb8888)  // 3 marker
  #expect(pixels[59 * 64 + 31] == PixelColor32.gray.xrgb8888)  // 6 marker
  #expect(pixels[31 * 64 + 31] == PixelColor32.black.xrgb8888)  // boss covers red
  #expect(pixels[20 * 64 + 30] == PixelColor32.black.xrgb8888)  // broad hour hand
  #expect(pixels[10 * 64 + 31] == 0xff80_0000)  // half coverage red over black
  #expect(pixels[7 * 64 + 31] == 0xffc0_4040)  // thin red over grey marker
  for y in 0..<64 {
    for x in 0..<32 {
      // The raw signal indicator intentionally occupies the upper right corner.
      if (2..<6).contains(y) && (58..<62).contains(63 - x) { continue }
      let left = pixels[y * 64 + x]
      let right = pixels[y * 64 + 63 - x]
      // A fractional edge close to a byte-rounding tie can differ by one.
      for shift in [0, 8, 16] {
        #expect(abs(Int((left >> shift) & 255) - Int((right >> shift) & 255)) <= 1)
      }
    }
  }
}

@Test("03:15:30 composition places the second hand below centre and moving hour hand past three")
func analogueQuarterPastThree() {
  let pixels = renderAnalogue(analogueSnapshot(3, 15, 30))
  #expect(pixels[54 * 64 + 31] == 0xffff_8080)
  #expect(pixels[34 * 64 + 46] == PixelColor32.black.xrgb8888)
  // At (44, 31), the hour and minute top edges cross the cell at about
  // y=31.683 and y=31.403 at its midpoint. Their black coverage bytes are
  // 81 and 152, which darken white to 174 and then 70.
  #expect(pixels[31 * 64 + 44] == 0xff46_4646)
  #expect(pixels[31 * 64 + 31] == PixelColor32.black.xrgb8888)
  #expect(pixels != renderAnalogue(analogueSnapshot(3, 15, 30, 500_000)))
}

@Test("Unknown time shows a dial and never invents midnight hands")
func analogueUnknown() {
  let pixels = renderAnalogue(analogueSnapshot(0, 0, 0, unknown: true))
  #expect(pixels[31 * 64 + 31] == PixelColor32.white.xrgb8888)
  #expect(pixels[20 * 64 + 31] == PixelColor32.white.xrgb8888)
}

@Test("Redrawing unknown time clears the previous hands from the same framebuffer")
func analogueRedrawClearsHandPixels() {
  let unknown = analogueSnapshot(0, 0, 0, unknown: true)
  let expected = renderAnalogue(unknown)
  withAnalogue { face, output in
    var context = DrawingContext(
      framebuffer: output, contextSize: PixelSize(width: 64, height: 64), pixelFormat: .bgrx8888)!
    #expect(face.render(into: &context, displaySnapshot: analogueSnapshot(12, 0, 0)))
    #expect(output[31 * 64 + 31] == PixelColor32.black.xrgb8888)
    #expect(face.render(into: &context, displaySnapshot: unknown))
    #expect(Array(output) == expected)
  }
}

@Test("The analogue face is usable through the existing Renderer")
func analogueRenderer() {
  withAnalogue { face, output in
    var request = HUB75RenderRequest(
      generation: 0, framebuffer: output.baseAddress, width: 64, height: 64,
      presentation_time_us: 0, deadline_us: 1000)
    let renderer = Renderer(clockFace: face)
    RenderHostTime.withTimestamps(Array(repeating: 0, count: 64 * 20)) {
      #expect(renderer.render(&request, displaySnapshot: analogueSnapshot(12, 0, 0)))
    }
    request.framebuffer = nil
    RenderHostTime.withTimestamps([]) {
      #expect(!renderer.render(&request, displaySnapshot: analogueSnapshot(12, 0, 0)))
    }
  }
}

@Test("An expired analogue deadline leaves the framebuffer untouched", arguments: [UInt64(1000), 1001])
func analogueLateStart(_ now: UInt64) {
  withAnalogue { face, output in
    var context = DrawingContext(
      framebuffer: output, contextSize: PixelSize(width: 64, height: 64), pixelFormat: .bgrx8888,
      renderDeadline: RenderDeadline(timeUs: 1000))!
    RenderHostTime.withTimestamps([now]) {
      #expect(
        !face.render(
          into: &context, displaySnapshot: analogueSnapshot(12, 0, 0)))
      #expect(RenderHostTime.readCount == 1)
    }
    #expect(output.allSatisfy { $0 == analogueSentinel })
  }
}

@Test("Analogue clearing stops before an expired row and skips the dial", arguments: [0, 1, 32, 63])
func analogueCancelledRow(_ completedRows: Int) {
  withAnalogue { face, output in
    let times = Array(repeating: UInt64(999), count: completedRows) + [1000]
    var context = DrawingContext(
      framebuffer: output, contextSize: PixelSize(width: 64, height: 64), pixelFormat: .bgrx8888,
      renderDeadline: RenderDeadline(timeUs: 1000))!
    RenderHostTime.withTimestamps(times) {
      #expect(
        !face.render(
          into: &context, displaySnapshot: analogueSnapshot(12, 0, 0)))
      #expect(context.status == .deadlineExceeded && RenderHostTime.readCount == times.count)
    }
    for index in output.indices {
      #expect(output[index] == (index < completedRows * 64 ? PixelColor32.black.xrgb8888 : analogueSentinel))
    }
  }
}

@Test("Analogue cancellation during the bezel leaves its accepted row and skips later layers")
func analogueBezelCancellation() {
  withAnalogue { face, output in
    var context = DrawingContext(
      framebuffer: output, contextSize: PixelSize(width: 64, height: 64), pixelFormat: .bgrx8888,
      renderDeadline: RenderDeadline(timeUs: 1000))!
    RenderHostTime.withTimestamps(Array(repeating: 999, count: 65) + [1000]) {
      #expect(!face.render(into: &context, displaySnapshot: analogueSnapshot(12, 0, 0)))
      #expect(context.status == .deadlineExceeded && RenderHostTime.readCount == 66)
    }
    #expect(output[31] > PixelColor32.black.xrgb8888 && output[31] < PixelColor32.gray.xrgb8888)
    #expect(output[31] == output[32])
    #expect(output.dropFirst(64).allSatisfy { $0 == PixelColor32.black.xrgb8888 })
  }
}

@Test("Analogue rejects a drawing context with dimensions that differ from its layout")
func analogueMismatchedSurface() {
  withAnalogue { face, output in
    var context = DrawingContext(
      framebuffer: output, contextSize: PixelSize(width: 63, height: 64), pixelFormat: .bgrx8888,
      renderDeadline: RenderDeadline(timeUs: 1000))!
    RenderHostTime.withTimestamps([]) {
      #expect(!face.render(into: &context, displaySnapshot: analogueSnapshot(12, 0, 0)))
    }
    #expect(output.allSatisfy { $0 == analogueSentinel })
  }
}

// Optional reproducible artefact generation, using exactly the production face.
// SK_ANALOGUE_PREVIEW_DIRECTORY=/absolute/path swift test --filter analoguePreviews
@Test("Export optional 64x64 production rendering previews")
func analoguePreviews() throws {
  guard let directory = ProcessInfo.processInfo.environment["SK_ANALOGUE_PREVIEW_DIRECTORY"] else { return }
  try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
  for (name, snapshot) in [
    ("120000", analogueSnapshot(12, 0, 0)), ("031530", analogueSnapshot(3, 15, 30)),
    ("101008-5", analogueSnapshot(10, 10, 8, 500_000)), ("115959-5", analogueSnapshot(11, 59, 59, 500_000)),
    ("unknown", analogueSnapshot(0, 0, 0, unknown: true, signalHigh: true)),
    ("seconds-only", analogueSnapshot(0, 0, 8, 500_000, unknown: true, secondKnown: true, signalHigh: true)),
    ("minute-only", analogueSnapshot(0, 15, 30, 500_000, hourKnown: false, signalHigh: true)),
    ("hour-only", analogueSnapshot(10, 0, 8, 500_000, minuteKnown: false, signalHigh: true)),
  ] {
    let pixels = renderAnalogue(snapshot)
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
        samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 64 * 3, bitsPerPixel: 24))
    let data = try #require(bitmap.bitmapData)
    for index in pixels.indices {
      data[index * 3] = UInt8((pixels[index] >> 16) & 255)
      data[index * 3 + 1] = UInt8((pixels[index] >> 8) & 255)
      data[index * 3 + 2] = UInt8(pixels[index] & 255)
    }
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
  }
}

private func analogueSnapshot(
  _ hour: Int, _ minute: Int, _ second: Int, _ microseconds: UInt32 = 0, unknown: Bool = false,
  hourKnown: Bool? = nil, minuteKnown: Bool? = nil, secondKnown: Bool? = nil, signalHigh: Bool = false
) -> MSFDisplaySnapshot {
  MSFDisplaySnapshot(
    clockSnapshot: ClockSnapshot(
      calendarDateTime: CalendarDateTimeComponents(
        year: 2026, month: 10, dayOfMonth: 20, dayOfWeek: 2,
        hour: hour, minute: minute, second: second, timeZone: .bst),
      clockState: ClockState(
        year: .unknown, month: .unknown, dayOfMonth: .unknown, dayOfWeek: .unknown,
        hour: (hourKnown ?? !unknown) ? .confirmed : .unknown,
        minute: (minuteKnown ?? !unknown) ? .confirmed : .unknown, timeZone: .unknown),
      subsecondMicroseconds: microseconds, hasSecondTiming: secondKnown ?? !unknown),
    secondPhaseBin: nil, timestamp: 0, signalHigh: signalHigh, highBins: 0, lowBins: 0)
}

private func renderAnalogue(_ snapshot: MSFDisplaySnapshot, timeSource: TimeSource = .msf) -> [UInt32] {
  var result: [UInt32] = []
  withAnalogue(timeSource: timeSource) { face, output in
    var context = DrawingContext(
      framebuffer: output, contextSize: PixelSize(width: 64, height: 64), pixelFormat: .bgrx8888)!
    #expect(face.render(into: &context, displaySnapshot: snapshot))
    #expect(output.allSatisfy { $0 >> 24 == 255 })
    result = Array(output)
  }
  return result
}

private func withAnalogue(
  timeSource: TimeSource = .msf, _ body: (AnalogueClockFace, UnsafeMutableBufferPointer<UInt32>) -> Void
) {
  var output = Array(repeating: analogueSentinel, count: 4098)
  output.withUnsafeMutableBufferPointer { outputBuffer in
    let face = AnalogueClockFace(
      size: PixelSize(width: 64, height: 64),
      configuration: ClockConfiguration(timeSource: timeSource, theme: .standard, timeZone: .uk)
    )
    body(face, .init(start: outputBuffer.baseAddress!.advanced(by: 1), count: 4096))
  }
  #expect(output.first == analogueSentinel && output.last == analogueSentinel)
}

@Test("Optional host rendering timing sample")
func analogueBenchmark() {
  guard ProcessInfo.processInfo.environment["SK_ANALOGUE_BENCHMARK"] == "1" else { return }
  let iterations = 600
  withAnalogue { face, output in
    let started = DispatchTime.now().uptimeNanoseconds
    var context = DrawingContext(
      framebuffer: output, contextSize: PixelSize(width: 64, height: 64), pixelFormat: .bgrx8888)!
    for frame in 0..<iterations {
      let snapshot = analogueSnapshot(10, 10, frame / 60, UInt32(frame % 60) * 16_666)
      #expect(face.render(into: &context, displaySnapshot: snapshot))
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - started
    print("ANALOGUE_HOST average_us=\(Double(elapsed) / Double(iterations) / 1000) frames=\(iterations)")
  }
}

@Test("Provisional hands appear independently, ignoring unavailable field placeholders", arguments: 0..<8)
func analogueIndependentHands(_ mask: Int) throws {
  let hourKnown = mask & 4 != 0
  let minuteKnown = mask & 2 != 0
  let secondKnown = mask & 1 != 0
  // The unknown fields deliberately contain nonzero plausible values.
  let snapshot = analogueSnapshot(
    3, 30, 45, 500_000,
    hourKnown: hourKnown, minuteKnown: minuteKnown, secondKnown: secondKnown)
  #expect(!snapshot.clockSnapshot.hasAcquiredTime)
  let angles = AnalogueClockFace.HandAngles(snapshot: snapshot.clockSnapshot)
  #expect((angles.hour != nil) == hourKnown)
  #expect((angles.minute != nil) == minuteKnown)
  #expect((angles.second != nil) == secondKnown)
  if let hour = angles.hour {
    let expected: Float = 90 + (minuteKnown ? 15 + (secondKnown ? 45.5 / 120 : 0) : 0)
    #expect(abs(hour * 180 / .pi - expected) < 0.0001)
  }
  if let minute = angles.minute {
    #expect(abs(minute * 180 / .pi - (180 + (secondKnown ? 4.55 : 0))) < 0.0001)
  }
  if let second = angles.second { #expect(abs(second * 180 / .pi - 273) < 0.0001) }

  let pixels = renderAnalogue(snapshot)
  let baseline = renderAnalogue(analogueSnapshot(0, 0, 0, unknown: true))
  let black = PixelColor32.black.xrgb8888
  #expect((pixels[33 * 64 + 42] == black || pixels[36 * 64 + 42] == black) == hourKnown)
  #expect((pixels[49 * 64 + 30] == black || pixels[49 * 64 + 31] == black) == minuteKnown)
  let redPresent = (29...32).contains { y in
    let pixel = pixels[y * 64 + 8]
    return ((pixel >> 16) & 255) > ((pixel >> 8) & 255)
  }
  #expect(redPresent == secondKnown)
  #expect((pixels[31 * 64 + 31] != baseline[31 * 64 + 31]) == (hourKnown || minuteKnown || secondKnown))
}

@Test("Unknown finer fields cannot move known coarser hands")
func analogueUnknownInterpolation() {
  for (hour, minute, second) in [(3, 5, 10), (3, 59, 59)] {
    let angles = AnalogueClockFace.HandAngles(
      snapshot: analogueSnapshot(
        hour, minute, second, 900_000,
        hourKnown: true, minuteKnown: false, secondKnown: true
      ).clockSnapshot)
    #expect(angles.hour == Float.pi / 2)
    #expect(angles.minute == nil)
  }
  let first = renderAnalogue(
    analogueSnapshot(
      17, 15, 59, 999_999,
      hourKnown: false, minuteKnown: true, secondKnown: false))
  let second = renderAnalogue(
    analogueSnapshot(
      2, 15, 1, 1,
      hourKnown: false, minuteKnown: true, secondKnown: false))
  #expect(first == second)
}

@Test(
  "Analogue signal indicator matches analytical raw-level flashing before and after acquisition",
  arguments: [false, true], [false, true])
func analogueSignalIndicator(_ unknown: Bool, _ high: Bool) {
  let clockFaceSize = PixelSize(width: 64, height: 64)
  let pixels = renderAnalogue(analogueSnapshot(10, 10, 8, unknown: unknown, signalHigh: high))
  let other = renderAnalogue(analogueSnapshot(10, 10, 8, unknown: unknown, signalHigh: !high))
  let frame = AnalyticalClockFace.LayoutMetrics(size: clockFaceSize).indicatorFrame
  #expect(frame == AnalogueClockFace.LayoutMetrics(size: clockFaceSize).indicatorFrame)
  let expected =
    high ? AnalogueClockFace.Theme.standard.indicatorHighColor : AnalogueClockFace.Theme.standard.indicatorLowColor
  for y in 0..<clockFaceSize.height {
    for x in 0..<clockFaceSize.width {
      let inside = x >= frame.minX && x < frame.maxX && y >= frame.minY && y < frame.maxY
      if inside {
        #expect(pixels[y * clockFaceSize.height + x] == expected.xrgb8888)
      } else {
        #expect(pixels[y * clockFaceSize.height + x] == other[y * clockFaceSize.height + x])
      }
    }
  }
}

@Test("NTP analogue rendering omits the MSF indicator and ignores raw signal changes")
func analogueNTPIndicator() {
  let high = analogueSnapshot(0, 0, 0, unknown: true, signalHigh: true)
  let low = analogueSnapshot(0, 0, 0, unknown: true)
  let pixels = renderAnalogue(high, timeSource: .ntp)
  #expect(pixels == renderAnalogue(low, timeSource: .ntp))
  let msf = renderAnalogue(high)
  let frame = AnalogueClockFace.LayoutMetrics(size: PixelSize(width: 64, height: 64)).indicatorFrame
  for y in 0..<64 {
    for x in 0..<64 {
      let inside = (frame.minX..<frame.maxX).contains(x) && (frame.minY..<frame.maxY).contains(y)
      #expect((pixels[y * 64 + x] != msf[y * 64 + x]) == inside)
    }
  }
}

@Test(
  "Acquired hand rendering is independent of current radio confidence",
  arguments: [
    EpistemicState.unknown, .candidate, .supported, .confirmed,
  ])
func analogueAcquiredConfidence(_ confidence: EpistemicState) {
  let reference = analogueSnapshot(3, 15, 30, 500_000)
  let time = reference.clockSnapshot.calendarDateTime
  let state = ClockState(
    year: .unknown, month: .unknown, dayOfMonth: .unknown, dayOfWeek: .unknown,
    hour: confidence, minute: confidence, timeZone: .unknown)
  let estimate = ClockSnapshot(
    calendarDateTime: time, clockState: state,
    subsecondMicroseconds: 500_000, hasSecondTiming: true, hasAcquiredTime: true)
  let actual = MSFDisplaySnapshot(raw: reference, clockSnapshot: estimate)
  #expect(renderAnalogue(actual) == renderAnalogue(reference))
  #expect(actual.clockSnapshot.clockState.hour == confidence && actual.clockSnapshot.clockState.minute == confidence)
}

@Test("Real acquired clock keeps all hands visible and advancing after complete evidence decay")
func analogueModelHoldover() throws {
  var clock = MSFClockModel()
  // Independent packed frame fixture: 2026-09-29 17:42 BST.
  _ = clock.receive(
    completedFrame: MSFCompletedFrame(
      aBits: 0x132_694b_c27e, bBits: 0x6,
      dataCount: 59, hasOpeningMarker: true, closingMarkerTime: 10_000_000))
  let now: UInt64 = 10_000_000 + 35 * 60_000_000 + 12_250_000
  let first = try #require(clock.currentSnapshot(at: now))
  let second = try #require(clock.currentSnapshot(at: now + 500_000))
  #expect(first.clockState.hour == .unknown && first.clockState.minute == .unknown)
  #expect(second.clockState.hour == .unknown && second.clockState.minute == .unknown)
  let firstAngles = AnalogueClockFace.HandAngles(snapshot: first)
  let secondAngles = AnalogueClockFace.HandAngles(snapshot: second)
  for (a, b) in [
    (firstAngles.hour, secondAngles.hour), (firstAngles.minute, secondAngles.minute),
    (firstAngles.second, secondAngles.second),
  ] {
    #expect(try #require(b) > #require(a))
  }
  let raw = analogueSnapshot(0, 0, 0, unknown: true)
  let firstPixels = renderAnalogue(MSFDisplaySnapshot(raw: raw, clockSnapshot: first))
  let secondPixels = renderAnalogue(MSFDisplaySnapshot(raw: raw, clockSnapshot: second))
  #expect(firstPixels == renderAnalogue(analogueSnapshot(18, 17, 12, 250_000)))
  #expect(secondPixels == renderAnalogue(analogueSnapshot(18, 17, 12, 750_000)))
  #expect(firstPixels != secondPixels)
}

@Test("Analytical time diagnostics retain unknown evidence despite an acquired estimate")
func analyticalAcquiredUnknownEvidence() {
  let time = analogueSnapshot(3, 15, 30).clockSnapshot.calendarDateTime
  let provisional = ClockSnapshot(
    calendarDateTime: time, clockState: .unknown, hasSecondTiming: true)
  let acquired = ClockSnapshot(
    calendarDateTime: time, clockState: .unknown,
    hasSecondTiming: true, hasAcquiredTime: true)
  let known = analogueSnapshot(3, 15, 30).clockSnapshot
  func timePixels(_ snapshot: ClockSnapshot) -> [UInt32] {
    var pixels = Array(repeating: UInt32(0), count: 4096)
    pixels.withUnsafeMutableBufferPointer { buffer in
      let clockFaceSize = PixelSize(width: 64, height: 64)
      var context = DrawingContext(framebuffer: buffer, contextSize: clockFaceSize, pixelFormat: .bgrx8888)!
      let completed = AnalyticalClockFace(
        size: clockFaceSize,
        configuration: ClockConfiguration(timeSource: .msf, theme: .standard, timeZone: .uk)
      ).drawClockTime(
        into: &context,
        clockSnapshot: snapshot, theme: .standard)
      #expect(completed)
    }
    return pixels
  }
  #expect(timePixels(acquired) == timePixels(provisional))
  #expect(timePixels(acquired) != timePixels(known))
}
