//
//  MSFClockModel.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-01.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// Foreground-only temporal interpretation of completed MSF frames. Partial
// frames never move the Pico minute anchor; a fully confirmed frame may do so.
struct MSFClockModel {
  private(set) var currentCalendarDateTime: CalendarDateTimeComponents?
  private(set) var anchorMarkerTime: UInt64?
  private(set) var evidence = MSFEvidenceFrame()

  private var anchorCalendarDateTime: CalendarDateTimeComponents?
  private var currentMinuteIndex: UInt64 = 0
  private var lastObservedMarkerTime: UInt64?
  // Nil means no B58 hypothesis has established GMT/BST; the calendar timeZone
  // is also nil. Once established, the zone is retained as evidence ages.
  private var summerTimeHypothesis: Bool?

  var isAcquired: Bool { anchorCalendarDateTime != nil }

  mutating func start(from supported: MSFSupportedAcquisition) -> MSFClockEvent {
    guard !isAcquired else { return .stale }
    anchorCalendarDateTime = supported.anchorCalendarDateTime
    anchorMarkerTime = supported.anchorMarkerTime
    currentCalendarDateTime = supported.currentCalendarDateTime
    currentMinuteIndex = supported.minuteIndex
    lastObservedMarkerTime = supported.lastMarkerTime
    evidence = supported.evidence
    summerTimeHypothesis = supported.summerTime
    return .acquiredFromPartial(supported.currentCalendarDateTime)
  }

  mutating func receive(completedFrame: MSFCompletedFrame) -> MSFClockEvent {
    let decoded = completedFrame.decode()
    let confirmedCalendarDateTime: CalendarDateTimeComponents?
    if decoded.decodeStatus == .valid,
      let dateTime = decoded.calendarDateTime,
      let summerTime = completedFrame.summerTime
    {
      confirmedCalendarDateTime = dateTime.settingTimeZone(summerTime ? .bst : .gmt)
    } else {
      confirmedCalendarDateTime = nil
    }

    guard let anchorMarkerTime, let anchorCalendarDateTime, let currentCalendarDateTime else {
      guard let confirmedCalendarDateTime,
        let logicalFrame = completedFrame.logicalFrame()
      else { return .unacquired }

      acquire(
        calendarDateTime: confirmedCalendarDateTime,
        from: logicalFrame, at: completedFrame.closingMarkerTime)
      return .acquired(confirmedCalendarDateTime)
    }
    guard let lastObservedMarkerTime,
      completedFrame.closingMarkerTime > lastObservedMarkerTime,
      completedFrame.closingMarkerTime >= anchorMarkerTime
    else { return .stale }

    let grid = MSFMinuteGrid.position(completedFrame.closingMarkerTime - anchorMarkerTime)
    if let confirmedCalendarDateTime {
      guard let logicalFrame = completedFrame.logicalFrame() else { return .unacquired }

      guard let predicted = anchorCalendarDateTime.advanced(byMinutes: grid.index)
      else {
        acquire(
          calendarDateTime: confirmedCalendarDateTime,
          from: logicalFrame,
          at: completedFrame.closingMarkerTime)
        return .acquired(confirmedCalendarDateTime)
      }

      let comparablePrediction =
        summerTimeHypothesis == nil
        ? predicted.settingTimeZone(confirmedCalendarDateTime.timeZone) : predicted
      acquire(
        calendarDateTime: confirmedCalendarDateTime,
        from: logicalFrame, at: completedFrame.closingMarkerTime)
      return confirmedCalendarDateTime == comparablePrediction
        ? .corroborated(confirmedCalendarDateTime)
        : .resynchronised(expected: predicted, received: confirmedCalendarDateTime)
    }

    guard grid.index > currentMinuteIndex else { return .stale }
    guard MSFMinuteGrid.isAligned(grid.error) else {
      return .offGrid(phaseErrorUs: grid.error)
    }

    let missedMinutes = grid.index - currentMinuteIndex - 1
    guard
      let beforeObservation = evidence.projectUnobservedMinutes(
        from: currentCalendarDateTime, by: missedMinutes, predictSummerTime: summerTimeHypothesis != nil),
      var calendarDateTime = beforeObservation.advanced(byMinutes: 1)
    else {
      return .unacquired
    }
    var previousExpected = expectedFrame(from: calendarDateTime)
    evidence.projectExpectedTransition(
      fromExpectedFrame: expectedFrame(from: beforeObservation), toExpectedFrame: previousExpected)
    currentMinuteIndex = grid.index
    self.lastObservedMarkerTime = completedFrame.closingMarkerTime

    let logical = completedFrame.logicalFrame()
    if summerTimeHypothesis == nil, let logical,
      logical.analyze().fixedIdentifier == .valid,
      let observed = logical.bit(at: MSFLogicalLayout.summerTimePosition, channel: .b)
    {
      summerTimeHypothesis = observed
      let timeZone: TimeZone = observed ? .bst : .gmt
      calendarDateTime = calendarDateTime.settingTimeZone(timeZone)
      self.anchorCalendarDateTime = anchorCalendarDateTime.settingTimeZone(timeZone)
      previousExpected = expectedFrame(from: calendarDateTime)
    }
    self.currentCalendarDateTime = calendarDateTime
    var contradictions: UInt8 = 0
    for position in MSFLogicalFrame.logicalRange {
      contradictions += evidence.observe(
        receivedBool: logical?.bits(atLogicalPosition: position),
        expectedA: previousExpected.bit(at: position, channel: .a),
        expectedB: previousExpected.bit(at: position, channel: .b),
        atPosition: position
      )
    }

    let validatedGroups =
      logical.map {
        evidence.restoreValidatedGroups(fromLogicalFrame: $0, matching: previousExpected)
      } ?? 0
    return .updated(
      calendarDateTime, missedMinutes: missedMinutes,
      contradictions: contradictions, validatedGroups: validatedGroups)
  }

  func currentSnapshot(at now: UInt64) -> ClockSnapshot? {
    guard let anchorMarkerTime, let projected = projectedState(at: now) else { return nil }
    // Follow the existing ordinary 60-second minute grid.
    let second = Int(((now - anchorMarkerTime) % MSFMinuteGrid.durationUs) / 1_000_000)
    return ClockSnapshot(
      calendarDateTime: projected.calendarDateTime,
      evidence: projected.evidence,
      second: second, subsecondMicroseconds: UInt32((now - anchorMarkerTime) % 1_000_000))
  }

  private mutating func acquire(
    calendarDateTime: CalendarDateTimeComponents,
    from logicalFrame: MSFLogicalFrame,
    at markerTime: UInt64
  ) {
    anchorCalendarDateTime = calendarDateTime
    currentCalendarDateTime = calendarDateTime
    anchorMarkerTime = markerTime
    lastObservedMarkerTime = markerTime
    currentMinuteIndex = 0
    evidence = MSFEvidenceFrame(confirmed: logicalFrame)
    summerTimeHypothesis = calendarDateTime.timeZone.map { $0 == .bst }
  }

  private func expectedFrame(from calendarDateTime: CalendarDateTimeComponents) -> MSFExpectedFrame {
    MSFExpectedFrame(
      calendarDateTime: calendarDateTime,
      predictSummerTime: summerTimeHypothesis != nil)
  }

  func projectedState(
    at now: UInt64
  ) -> (calendarDateTime: CalendarDateTimeComponents, evidence: MSFEvidenceFrame, index: UInt64)? {
    guard let currentCalendarDateTime,
      let targetIndex = projectedMinuteIndex(at: now)
    else {
      return nil
    }

    var projectedEvidence = evidence
    guard
      let calendarDateTime = projectedEvidence.projectUnobservedMinutes(
        from: currentCalendarDateTime, by: targetIndex - currentMinuteIndex,
        predictSummerTime: summerTimeHypothesis != nil)
    else { return nil }
    return (calendarDateTime, projectedEvidence, targetIndex)
  }

  func projectedMinuteIndex(at now: MSFTime) -> UInt64? {
    guard let anchorMarkerTime,
      currentCalendarDateTime != nil,
      now >= anchorMarkerTime
    else {
      return nil
    }

    let elapsedIndex = (now - anchorMarkerTime) / MSFMinuteGrid.durationUs
    return max(currentMinuteIndex, elapsedIndex)
  }
}

extension ClockState {

  fileprivate init(evidenceFrame evidence: MSFEvidenceFrame) {
    self.init(
      year: evidence.epistemicState(in: MSFField.year.positions),
      month: evidence.epistemicState(in: MSFField.month.positions),
      dayOfMonth: evidence.epistemicState(in: MSFField.dayOfMonth.positions),
      dayOfWeek: evidence.epistemicState(in: MSFField.dayOfWeek.positions),
      hour: evidence.epistemicState(in: MSFField.hour.positions),
      minute: evidence.epistemicState(in: MSFField.minute.positions),
      timeZone: evidence.second(
        atLogicalPosition: MSFLogicalLayout.summerTimePosition)?.b.state ?? .unknown)
  }
}

extension ClockSnapshot {
  fileprivate init(
    calendarDateTime: CalendarDateTimeComponents,
    evidence: MSFEvidenceFrame,
    second: Int,
    subsecondMicroseconds: UInt32
  ) {
    let calendarDateTime = calendarDateTime.with(second: second)
    let clockState = ClockState(evidenceFrame: evidence)
    self.init(
      calendarDateTime: calendarDateTime, clockState: clockState,
      subsecondMicroseconds: subsecondMicroseconds, hasSecondTiming: true, hasAcquiredTime: true)
  }
}
