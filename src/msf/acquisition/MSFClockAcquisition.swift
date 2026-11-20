//
//  MSFClockAcquisition.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-01.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// Foreground initial acquisition. Each hypothesis is an exact calendar minute at
// one fixed observed marker; received bits are never merged across minutes.
struct MSFClockAcquisition {
  static let hypothesisCapacity = 64
  static let historyCapacity = 8
  static let minimumInformativeFrames = 2

  private var hypotheses: InlineArray<64, MSFAcquisitionHypothesis> =
    .init(repeating: MSFAcquisitionHypothesis())
  private var history: InlineArray<8, MSFAcquisitionObservation> =
    .init(repeating: MSFAcquisitionObservation())
  private var historyCount = 0
  private var lastSeenMarkerTime: UInt64?

  private(set) var status = MSFAcquisitionStatus.unacquired
  private(set) var hypothesisCount = 0
  private(set) var informativeFrameCount = 0
  private(set) var exceedsCapacity = false
  private(set) var anchorMarkerTime: UInt64?
  private(set) var currentMinuteIndex: UInt64 = 0

  static var storageBytes: Int {
    MemoryLayout<InlineArray<64, MSFAcquisitionHypothesis>>.stride
      + MemoryLayout<InlineArray<8, MSFAcquisitionObservation>>.stride
  }

  func hypothesis(at index: Int) -> CalendarDateTimeComponents? {
    guard (0..<hypothesisCount).contains(index) else { return nil }
    return hypotheses[index].calendarDateTime.advanced(byMinutes: currentMinuteIndex)
  }

  var currentHypothesis: CalendarDateTimeComponents? {
    hypothesisCount == 1 ? hypothesis(at: 0) : nil
  }

  mutating func receive(completedFrame: MSFCompletedFrame) -> MSFAcquisitionEvent {
    // Main routes these directly to the authoritative decoder/clock path.
    guard completedFrame.decode().decodeStatus != .valid else {
      return .ignored(.confirmedFrame)
    }
    if let lastSeenMarkerTime, completedFrame.closingMarkerTime <= lastSeenMarkerTime {
      return .ignored(.staleMarker)
    }
    lastSeenMarkerTime = completedFrame.closingMarkerTime
    if let anchorMarkerTime {
      let grid = MSFMinuteGrid.position(completedFrame.closingMarkerTime - anchorMarkerTime)
      guard MSFMinuteGrid.isAligned(grid.error) else {
        clear()
        return .reset(.offGrid(phaseErrorUs: grid.error))
      }
      guard grid.index > currentMinuteIndex else { return .ignored(.staleMarker) }
      currentMinuteIndex = grid.index
    }
    guard let logicalFrame = completedFrame.logicalFrame() else {
      return .ignored(.insufficientData)
    }
    guard !completedFrame.hasOpeningMarker || (58...60).contains(completedFrame.dataCount)
    else {
      return .ignored(.invalidFrameLength)
    }
    let constraints = MSFAcquisitionConstraints(
      completedFrame: completedFrame,
      logicalFrame: logicalFrame)
    // A damaged identifier makes the whole frame untrustworthy. A partial
    // identifier is allowed; individual valid/indeterminate groups remain useful.
    guard constraints.identifierCompatible else {
      return .ignored(.invalidIdentifier)
    }
    // Identifier, reserved B bits, and Summer Time alone cannot count as
    // an independent date/time observation. Require usable A17...A51 data.
    if hypothesisCount == 0 {
      guard constraints.isInformative else { return .ignored(.uninformative) }
      return seed(completedFrame: completedFrame, constraints: constraints)
    }
    // Parity-only constraints can filter an already bounded set, but do
    // not count as another independent A-data observation for promotion.
    guard constraints.hasConstraints else { return .ignored(.uninformative) }
    var retained = 0
    for index in 0..<hypothesisCount {
      let candidate = hypotheses[index]

      guard
        let calendarDateTime = candidate.calendarDateTime.advanced(
          byMinutes: currentMinuteIndex)
      else {
        continue
      }

      if constraints.matches(
        expectedFrame: MSFExpectedFrame(
          calendarDateTime: calendarDateTime,
          predictSummerTime: false))
      {
        hypotheses[retained] = candidate
        retained += 1
      }
    }
    hypothesisCount = retained
    guard retained > 0 else {
      clear()
      return .reset(.incompatibleEvidence)
    }
    remember(completedFrame: completedFrame, at: currentMinuteIndex)
    if constraints.isInformative {
      informativeFrameCount = min(informativeFrameCount + 1, 255)
    }
    updateStatus()
    return .updated
  }

  /// Expose agreed candidate hour/minute values across retained hypotheses,
  /// with marker-derived second timing; date and time zone remain unknown.
  /// This does not promote acquisition, fabricate evidence or change the authoritative clock.
  func currentSnapshot(at now: MSFTime) -> ClockSnapshot? {
    guard let anchorMarkerTime, now >= anchorMarkerTime, hypothesisCount > 0 else { return nil }
    let index = max(currentMinuteIndex, (now - anchorMarkerTime) / MSFMinuteGrid.durationUs)

    guard let calendar = hypotheses[0].calendarDateTime.advanced(byMinutes: index)
    else { return nil }

    var hourKnown = true
    var minuteKnown = true
    for offset in 1..<hypothesisCount {
      guard let other = hypotheses[offset].calendarDateTime.advanced(byMinutes: index)
      else { return nil }

      hourKnown = hourKnown && other.hour == calendar.hour
      minuteKnown = minuteKnown && other.minute == calendar.minute
    }

    let displayCalendar = CalendarDateTimeComponents(
      year: nil,
      month: nil,
      dayOfMonth: nil,
      dayOfWeek: nil,
      hour: hourKnown ? calendar.hour : nil,
      minute: minuteKnown ? calendar.minute : nil,
      second: calendar.second,
      timeZone: nil
    )

    return ClockSnapshot(
      calendarDateTime: displayCalendar,
      clockState: ClockState(
        year: .unknown, month: .unknown, dayOfMonth: .unknown, dayOfWeek: .unknown,
        hour: hourKnown ? .candidate : .unknown, minute: minuteKnown ? .candidate : .unknown,
        timeZone: .unknown)
    ).withSecondTiming(at: now, minuteMarkerTime: anchorMarkerTime)
  }

  // Only a supported, unique acquisition can manufacture this handoff type.
  // Replay starts empty: calendar constraints do not fabricate radio evidence.
  func supportedAcquisition() -> MSFSupportedAcquisition? {
    guard status == .supported, let anchorMarkerTime,
      let lastSeenMarkerTime, historyCount > 0
    else { return nil }
    let anchor = hypotheses[0].calendarDateTime
    var evidence = MSFEvidenceFrame()
    var index = history[0].minuteIndex
    guard var calendarDateTime = anchor.advanced(byMinutes: index) else {
      return nil
    }

    var expectedFrame = MSFExpectedFrame(
      calendarDateTime: calendarDateTime,
      predictSummerTime: false)

    for observationIndex in 0..<historyCount {
      let observation = history[observationIndex]
      if index < observation.minuteIndex {
        guard
          let beforeObservation = evidence.projectUnobservedMinutes(
            from: calendarDateTime, by: observation.minuteIndex - index - 1,
            predictSummerTime: false, ageUnmodelledSummerTime: true),
          let next = beforeObservation.advanced(byMinutes: 1)
        else {
          return nil
        }

        let beforeExpected = MSFExpectedFrame(calendarDateTime: beforeObservation, predictSummerTime: false)
        let nextExpectedFrame = MSFExpectedFrame(
          calendarDateTime: next,
          predictSummerTime: false)
        evidence.projectExpectedTransition(
          fromExpectedFrame: beforeExpected, toExpectedFrame: nextExpectedFrame)
        index = observation.minuteIndex
        calendarDateTime = next
        expectedFrame = nextExpectedFrame
      }
      evidence.apply(observation: observation, matching: expectedFrame)
    }
    // Empty/ignored aligned observations since the last retained frame
    // still represent missed reinforcement opportunities.
    guard
      let latestCalendar = evidence.projectUnobservedMinutes(
        from: calendarDateTime, by: currentMinuteIndex - index,
        predictSummerTime: false, ageUnmodelledSummerTime: true)
    else { return nil }
    let summerTime = evidence.second(
      atLogicalPosition:
        MSFLogicalLayout.summerTimePosition)?.b.value
    var timeZone: TimeZone?
    if let summerTime {
      timeZone = summerTime ? .bst : .gmt
    }
    return MSFSupportedAcquisition(
      anchorCalendarDateTime: anchor.settingTimeZone(timeZone),
      anchorMarkerTime: anchorMarkerTime,
      currentCalendarDateTime: latestCalendar.settingTimeZone(timeZone),
      minuteIndex: currentMinuteIndex, lastMarkerTime: lastSeenMarkerTime,
      evidence: evidence, summerTime: summerTime)
  }

  private mutating func clear() {
    hypothesisCount = 0
    historyCount = 0
    informativeFrameCount = 0
    currentMinuteIndex = 0
    anchorMarkerTime = nil
    exceedsCapacity = false
    status = .unacquired
    // Retain lastSeenMarkerTime so the reset-triggering frame cannot be reused.
  }

  private mutating func updateStatus() {
    status =
      hypothesisCount > 1
      ? .ambiguous
      : informativeFrameCount >= Self.minimumInformativeFrames ? .supported : .candidate
  }

  private mutating func remember(completedFrame: MSFCompletedFrame, at index: UInt64) {
    if historyCount == Self.historyCapacity {
      for offset in 1..<Self.historyCapacity { history[offset - 1] = history[offset] }
      historyCount -= 1
    }
    history[historyCount] = MSFAcquisitionObservation(
      completedFrame: completedFrame, minuteIndex: index)
    historyCount += 1
  }

  private mutating func tooAmbiguous() -> MSFAcquisitionEvent {
    clear()
    status = .ambiguous
    exceedsCapacity = true
    return .tooAmbiguous
  }

  private mutating func seed(
    completedFrame: MSFCompletedFrame,
    constraints: MSFAcquisitionConstraints
  ) -> MSFAcquisitionEvent {
    // Enumerate small field domains, then independent legal date/time
    // combinations. Never enumerate the century's 52 million calendar minutes.
    var times: InlineArray<64, MSFAcquisitionTime> = .init(repeating: MSFAcquisitionTime())
    var timeCount = 0
    timeSearch: for hour in MSFCompletedFrame.validHourRange {
      guard constraints.matchesBCDValue(hour, inField: .hour) else { continue }
      for minute in MSFCompletedFrame.validMinuteRange {
        guard constraints.matchesBCDValue(minute, inField: .minute) else {
          continue
        }
        let bits =
          MSFExpectedFrame.bcdBits(forValue: hour, inField: .hour)
          | MSFExpectedFrame.bcdBits(forValue: minute, inField: .minute)
        guard
          constraints.matchesParity(
            expectedABits: bits, parityGroup: MSFLogicalLayout.hourMinuteParity)
        else { continue }
        if timeCount == Self.hypothesisCapacity {
          timeCount += 1
          break timeSearch
        }
        times[timeCount] = MSFAcquisitionTime(hour: UInt8(hour), minute: UInt8(minute))
        timeCount += 1
      }
    }
    guard timeCount > 0 else {
      clear()
      return .reset(.noLegalCalendarTime)
    }
    hypothesisCount = 0
    for year in MSFCompletedFrame.validYearRange {
      guard constraints.matchesBCDValue(year, inField: .year) else { continue }
      let yearBits = MSFExpectedFrame.bcdBits(forValue: year, inField: .year)
      guard
        constraints.matchesParity(
          expectedABits: yearBits, parityGroup: MSFLogicalLayout.yearParity)
      else { continue }
      for month in MSFCompletedFrame.validMonthRange {
        guard constraints.matchesBCDValue(month, inField: .month) else { continue }
        let monthBits = MSFExpectedFrame.bcdBits(forValue: month, inField: .month)
        for day: UInt8
          in 1...UInt8(
            CalendarDateTimeComponents.daysInMonth(Int(month), year: 2000 + Int(year)))
        {
          guard constraints.matchesBCDValue(day, inField: .dayOfMonth)
          else { continue }
          let monthDayBits =
            monthBits
            | MSFExpectedFrame.bcdBits(forValue: day, inField: .dayOfMonth)
          guard
            constraints.matchesParity(
              expectedABits: monthDayBits,
              parityGroup: MSFLogicalLayout.monthDayParity),
            let weekday = CalendarDateTimeComponents.weekday(
              year: 2000 + Int(year), month: Int(month), day: Int(day))
          else { continue }
          let weekdayBits = MSFExpectedFrame.bcdBits(
            forValue: UInt8(weekday), inField: .dayOfWeek)
          guard constraints.matchesA(expectedBits: weekdayBits, inField: .dayOfWeek),
            constraints.matchesParity(
              expectedABits: weekdayBits,
              parityGroup: MSFLogicalLayout.dayOfWeekParity)
          else { continue }
          if timeCount > Self.hypothesisCapacity { return tooAmbiguous() }
          for timeIndex in 0..<timeCount {
            if hypothesisCount == Self.hypothesisCapacity { return tooAmbiguous() }
            hypotheses[hypothesisCount] = MSFAcquisitionHypothesis(
              year: UInt8(year), month: UInt8(month), day: UInt8(day),
              weekday: UInt8(weekday), hour: UInt8(times[timeIndex].hour),
              minute: UInt8(times[timeIndex].minute))
            hypothesisCount += 1
          }
        }
      }
    }
    guard hypothesisCount > 0 else {
      clear()
      return .reset(.noLegalCalendarTime)
    }
    exceedsCapacity = false
    anchorMarkerTime = completedFrame.closingMarkerTime
    currentMinuteIndex = 0
    informativeFrameCount = 1
    historyCount = 0
    remember(completedFrame: completedFrame, at: 0)
    updateStatus()
    return .updated
  }
}

// Six bytes per hypothesis, rather than a full evidence frame per candidate.
private struct MSFAcquisitionHypothesis {
  var year: UInt8 = 0
  var month: UInt8 = 0
  var day: UInt8 = 0
  var weekday: UInt8 = 0
  var hour: UInt8 = 0
  var minute: UInt8 = 0

  var calendarDateTime: CalendarDateTimeComponents {
    CalendarDateTimeComponents(
      year: 2000 + Int(year), month: Int(month), dayOfMonth: Int(day),
      dayOfWeek: Int(weekday), hour: Int(hour), minute: Int(minute),
      second: 0, timeZone: nil)
  }
}

private struct MSFAcquisitionTime {
  var hour: UInt8 = 0
  var minute: UInt8 = 0
}

// Only the newest eight usable frames are retained for honest replay.
// Older constraints still narrow the hypotheses, but supply no fabricated
// confidence after they leave this bounded history. Each record is 32 bytes.
private struct MSFAcquisitionObservation {
  var aBits: UInt64 = 0
  var bBits: UInt64 = 0
  var unknownBits: UInt64 = 0
  var minuteIndex: UInt64 = 0

  init() {}
  init(completedFrame: MSFCompletedFrame, minuteIndex: UInt64) {
    aBits = completedFrame.aBits
    bBits = completedFrame.bBits
    unknownBits = completedFrame.unknownBits
    self.minuteIndex = minuteIndex
  }
}

private struct MSFAcquisitionConstraints {
  let analysis: MSFStructureAnalysis
  let aBits: UInt64
  let bBits: UInt64
  private var aKnown: UInt64
  private var bKnown: UInt64
  let knownSummerTime: Bool?
  let identifierCompatible: Bool

  init(completedFrame: MSFCompletedFrame, logicalFrame: MSFLogicalFrame) {
    analysis = logicalFrame.analyze()
    aBits = completedFrame.aBits
    bBits = completedFrame.bBits
    aKnown =
      ~completedFrame.unknownBits
      & MSFLogicalFrame.packedMask(
        for: MSFField.year.positions.lowerBound...MSFField.minute.positions.upperBound)
    bKnown =
      ~completedFrame.unknownBits
      & MSFLogicalFrame.packedMask(
        for:
          MSFLogicalLayout.yearParity
          .parityPosition...MSFLogicalLayout.hourMinuteParity.parityPosition)
    var identifierMatches = true
    // Shared analysis reports indeterminate when any identifier bit is nil.
    // A known wrong identifier bit is still grounds to distrust this frame.
    for position in MSFLogicalLayout.identifier {
      if let received = logicalFrame.bit(at: position, channel: .a),
        received != MSFLogicalLayout.identifierBit(at: position)
      {
        identifierMatches = false
      }
    }
    identifierCompatible = identifierMatches
    knownSummerTime =
      analysis.fixedIdentifier == .valid
      ? logicalFrame.bit(at: MSFLogicalLayout.summerTimePosition, channel: .b) : nil
    excludeInvalid(
      parityGroup: MSFLogicalLayout.yearParity, result: analysis.yearParity)
    excludeInvalid(
      parityGroup: MSFLogicalLayout.monthDayParity, result: analysis.monthDayParity)
    excludeInvalid(
      parityGroup: MSFLogicalLayout.dayOfWeekParity, result: analysis.dayOfWeekParity)
    excludeInvalid(
      parityGroup: MSFLogicalLayout.hourMinuteParity, result: analysis.hourMinuteParity)
  }

  var isInformative: Bool { aKnown != 0 }
  var hasConstraints: Bool { aKnown != 0 || bKnown != 0 }

  private mutating func excludeInvalid(parityGroup: MSFParityGroup, result: MSFStructureResult) {
    if result == .invalid {
      aKnown &= ~MSFLogicalFrame.packedMask(for: parityGroup.dataPositions)
      bKnown &=
        ~(UInt64(1)
        << (MSFLogicalFrame.logicalRange.upperBound - parityGroup.parityPosition))
    }
  }

  func bit(at position: Int, channel: MSFChannel) -> Bool? {
    let mask = UInt64(1) << (MSFLogicalFrame.logicalRange.upperBound - position)
    switch channel {
    case .a: return aKnown & mask == 0 ? nil : aBits & mask != 0
    case .b: return bKnown & mask == 0 ? nil : bBits & mask != 0
    }
  }

  func matchesA(expectedBits: UInt64, inField field: MSFField) -> Bool {
    let mask = aKnown & MSFLogicalFrame.packedMask(for: field.positions)
    return (aBits ^ expectedBits) & mask == 0
  }

  func matchesBCDValue(_ value: UInt8, inField field: MSFField) -> Bool {
    matchesA(
      expectedBits: MSFExpectedFrame.bcdBits(forValue: value, inField: field), inField: field)
  }

  func matchesParity(expectedABits: UInt64, parityGroup: MSFParityGroup) -> Bool {
    guard let received = bit(at: parityGroup.parityPosition, channel: .b) else { return true }
    let ones = (expectedABits & MSFLogicalFrame.packedMask(for: parityGroup.dataPositions))
      .nonzeroBitCount
    return received == (ones % 2 == 0)
  }

  func matches(expectedFrame: MSFExpectedFrame) -> Bool {
    for position in MSFLogicalFrame.logicalRange {
      if let receivedBit = bit(at: position, channel: .a),
        expectedFrame.bit(at: position, channel: .a) != receivedBit
      {
        return false
      }
      if let receivedBit = bit(at: position, channel: .b),
        expectedFrame.bit(at: position, channel: .b) != receivedBit
      {
        return false
      }
    }
    return true
  }
}

extension MSFEvidenceFrame {
  fileprivate mutating func apply(
    observation: MSFAcquisitionObservation,
    matching expectedFrame: MSFExpectedFrame
  ) {
    let completedFrame = MSFCompletedFrame(
      aBits: observation.aBits, bBits: observation.bBits,
      unknownBits: observation.unknownBits,
      dataCount: 43, hasOpeningMarker: false)
    guard let logicalFrame = completedFrame.logicalFrame() else { return }
    let constraints = MSFAcquisitionConstraints(
      completedFrame: completedFrame,
      logicalFrame: logicalFrame)
    for position in MSFLogicalFrame.logicalRange {
      let observedA =
        position <= MSFField.minute.positions.upperBound
        ? constraints.bit(at: position, channel: .a)
        : logicalFrame.bit(at: position, channel: .a)
      // Even the winner starts with zero confidence for an unobserved bit.
      observeSameLogicalValue(observedA, atLogicalPosition: position, channel: .a)
      if expectedFrame.bit(at: position, channel: .b) != nil {
        observeSameLogicalValue(
          constraints.bit(at: position, channel: .b),
          atLogicalPosition: position, channel: .b)
      }
    }
    observeSameLogicalValue(
      constraints.knownSummerTime,
      atLogicalPosition: MSFLogicalLayout.summerTimePosition, channel: .b)
    restoreValidatedGroups(fromLogicalFrame: logicalFrame, matching: expectedFrame)
  }
}
