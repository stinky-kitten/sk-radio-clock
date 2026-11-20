//
//  MSFEvidenceFrame.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-01.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// Evidence for logical *17...*59 positions. Updating a position requires the
// caller to assert that the observation concerns the same semantic value;
// consecutive transmitted minutes do not generally satisfy that condition.
struct MSFEvidenceFrame {
  private var seconds: InlineArray<43, MSFEpistemicSecond> =
    .init(repeating: MSFEpistemicSecond())

  init() {}

  init(confirmed expected: MSFExpectedFrame) {
    self.init()
    for position in MSFLogicalFrame.logicalRange {
      if let value = expected.bit(at: position, channel: .a) {
        confirmStructurallyValidatedValue(value, atLogicalPosition: position, channel: .a)
      }
      if let value = expected.bit(at: position, channel: .b) {
        confirmStructurallyValidatedValue(value, atLogicalPosition: position, channel: .b)
      }
    }
  }

  init(confirmed logical: MSFLogicalFrame) {
    self.init()
    for position in MSFLogicalFrame.logicalRange {
      if let value = logical.bit(at: position, channel: .a) {
        confirmStructurallyValidatedValue(value, atLogicalPosition: position, channel: .a)
      }
      if let value = logical.bit(at: position, channel: .b) {
        confirmStructurallyValidatedValue(value, atLogicalPosition: position, channel: .b)
      }
    }
  }

  func second(atLogicalPosition position: Int) -> MSFEpistemicSecond? {
    guard let index = MSFLogicalFrame.index(forLogicalPosition: position) else { return nil }
    return seconds[index]
  }

  @discardableResult
  mutating func observeSameLogicalValue(
    _ observedValue: Bool?, atLogicalPosition position: Int, channel: MSFChannel
  ) -> MSFEpistemicUpdate<Bool>? {
    guard let index = MSFLogicalFrame.index(forLogicalPosition: position) else { return nil }
    var second = seconds[index]
    let result: MSFEpistemicUpdate<Bool>
    switch channel {
    case .a:
      result = second.a.observeSameLogicalValue(observedValue)
    case .b:
      result = second.b.observeSameLogicalValue(observedValue)
    }
    seconds[index] = second
    return result
  }

  mutating func projectExpectedTransition(
    fromExpectedFrame old: MSFExpectedFrame,
    toExpectedFrame new: MSFExpectedFrame
  ) {
    for position in MSFLogicalFrame.logicalRange {
      guard let index = MSFLogicalFrame.index(forLogicalPosition: position) else { continue }
      var second = seconds[index]
      if let previous = old.bit(at: position, channel: .a),
        let expected = new.bit(at: position, channel: .a), previous != expected
      {
        second.a.transitionExpectedValue(to: expected)
      }
      if let previous = old.bit(at: position, channel: .b),
        let expected = new.bit(at: position, channel: .b), previous != expected
      {
        second.b.transitionExpectedValue(to: expected)
      }
      seconds[index] = second
    }
  }

  mutating func agePredictableBits(in expected: MSFExpectedFrame) {
    for position in MSFLogicalFrame.logicalRange {
      guard let index = MSFLogicalFrame.index(forLogicalPosition: position) else { continue }
      var second = seconds[index]
      if expected.bit(at: position, channel: .a) != nil { second.a.age() }
      if expected.bit(at: position, channel: .b) != nil { second.b.age() }
      seconds[index] = second
    }
  }

  mutating func projectUnobservedMinutes(
    from start: CalendarDateTimeComponents, by minutes: UInt64,
    predictSummerTime: Bool, ageUnmodelledSummerTime: Bool = false
  ) -> CalendarDateTimeComponents? {
    guard minutes > 0 else { return start }

    // The modelled positions stay fixed during a gap. Each loses one point
    // per minute, and transitions cannot seed exhausted evidence. Once the
    // maximum confidence is exhausted, only the calendar still changes.
    let replayCount = min(minutes, UInt64(MSFConfidence.maximum))
    var calendar = start
    var expected = MSFExpectedFrame(calendarDateTime: start, predictSummerTime: predictSummerTime)
    for _ in 0..<replayCount {
      guard let next = calendar.advanced(byMinutes: 1) else { return nil }
      let nextExpected = MSFExpectedFrame(calendarDateTime: next, predictSummerTime: predictSummerTime)
      projectExpectedTransition(fromExpectedFrame: expected, toExpectedFrame: nextExpected)
      agePredictableBits(in: nextExpected)
      if ageUnmodelledSummerTime, nextExpected.bit(at: MSFLogicalLayout.summerTimePosition, channel: .b) == nil {
        observeSameLogicalValue(nil, atLogicalPosition: MSFLogicalLayout.summerTimePosition, channel: .b)
      }
      calendar = next
      expected = nextExpected
    }
    return minutes == replayCount ? calendar : calendar.advanced(byMinutes: minutes - replayCount)
  }

  private mutating func confirmStructurallyValidatedValue(
    _ value: Bool,
    atLogicalPosition position: Int,
    channel: MSFChannel
  ) {
    guard let index = MSFLogicalFrame.index(forLogicalPosition: position) else { return }
    var second = seconds[index]
    switch channel {
    case .a: second.a.confirmValidatedValue(value)
    case .b: second.b.confirmValidatedValue(value)
    }
    seconds[index] = second
  }

  private func minimumAConfidence(in positions: ClosedRange<Int>) -> UInt8 {
    var lowest = UInt8.max
    for position in positions {
      guard let second = second(atLogicalPosition: position) else { return 0 }
      if second.a.confidence < lowest { lowest = second.a.confidence }
    }
    return lowest == UInt8.max ? 0 : lowest
  }

  func epistemicState(in positions: ClosedRange<Int>) -> EpistemicState {
    let confidence = minimumAConfidence(in: positions)
    switch confidence {
    case 0: return .unknown
    case 1...10: return .candidate
    case 11...20: return .supported
    default: return .confirmed
    }
  }

  @discardableResult
  mutating func restoreValidatedGroups(
    fromLogicalFrame logicalFrame: MSFLogicalFrame,
    matching expectedFrame: MSFExpectedFrame
  ) -> UInt8 {
    let analysis = logicalFrame.analyze()
    var restored: UInt8 = 0
    if restore(
      parityGroup: MSFLogicalLayout.yearParity, result: analysis.yearParity,
      logicalFrame: logicalFrame, expectedFrame: expectedFrame)
    {
      restored += 1
    }
    if restore(
      parityGroup: MSFLogicalLayout.monthDayParity, result: analysis.monthDayParity,
      logicalFrame: logicalFrame, expectedFrame: expectedFrame)
    {
      restored += 1
    }
    if restore(
      parityGroup: MSFLogicalLayout.dayOfWeekParity, result: analysis.dayOfWeekParity,
      logicalFrame: logicalFrame, expectedFrame: expectedFrame)
    {
      restored += 1
    }
    if restore(
      parityGroup: MSFLogicalLayout.hourMinuteParity, result: analysis.hourMinuteParity,
      logicalFrame: logicalFrame, expectedFrame: expectedFrame)
    {
      restored += 1
    }
    return restored
  }

  private mutating func restore(
    parityGroup: MSFParityGroup, result: MSFStructureResult,
    logicalFrame: MSFLogicalFrame,
    expectedFrame: MSFExpectedFrame
  ) -> Bool {
    guard result == .valid else { return false }
    for position in parityGroup.dataPositions {
      guard let predicted = expectedFrame.bit(at: position, channel: .a),
        logicalFrame.bit(at: position, channel: .a) == predicted
      else { return false }
    }
    guard let parity = expectedFrame.bit(at: parityGroup.parityPosition, channel: .b),
      logicalFrame.bit(at: parityGroup.parityPosition, channel: .b) == parity
    else { return false }
    for position in parityGroup.dataPositions {
      if let predicted = expectedFrame.bit(at: position, channel: .a) {
        confirmStructurallyValidatedValue(
          predicted, atLogicalPosition: position, channel: .a)
      }
    }
    confirmStructurallyValidatedValue(
      parity, atLogicalPosition: parityGroup.parityPosition, channel: .b)
    return true
  }
}

extension MSFEvidenceFrame {
  mutating func observe(
    receivedBool: Bool?,
    expectedBool: Bool?,
    atPosition position: Int,
    forChannel channel: MSFChannel
  ) -> Bool {
    guard let expectedBool else { return false }

    if let receivedBool, receivedBool != expectedBool { return true }

    observeSameLogicalValue(
      receivedBool,
      atLogicalPosition: position,
      channel: channel
    )

    return false
  }

  mutating func observe(
    receivedBool: MSFBits?,
    expectedA: Bool?,
    expectedB: Bool?,
    atPosition position: Int
  ) -> UInt8 {
    var contradictions: UInt8 = 0

    if observe(
      receivedBool: receivedBool?.a, expectedBool: expectedA, atPosition: position,
      forChannel: .a
    ) {
      contradictions += 1
    }

    if observe(
      receivedBool: receivedBool?.b, expectedBool: expectedB, atPosition: position,
      forChannel: .b)
    {
      contradictions += 1
    }

    return contradictions
  }
}
