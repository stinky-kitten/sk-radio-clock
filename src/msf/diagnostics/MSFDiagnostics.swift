//
//  MSFDiagnostics.swift
//  sk-radio-clock
//

func printClock(
  _ snapshot: ClockSnapshot, event: MSFClockEvent?,
  predicted: Bool = false
) {
  let eventName: StaticString
  var missedMinutes: UInt64 = 0
  var contradictions: UInt8 = 0
  var validatedGroups: UInt8 = 0
  var previous: CalendarDateTimeComponents?

  if predicted {
    eventName = "predicted"
  } else if let event {
    switch event {
    case .acquired:
      eventName = "acquired"
    case .acquiredFromPartial:
      eventName = "acquired from partial frames"
    case .updated(_, let missed, let conflicts, let groups):
      eventName = "updated"
      missedMinutes = missed
      contradictions = conflicts
      validatedGroups = groups
    case .corroborated:
      eventName = "corroborated"
    case .resynchronised(let expected, _):
      eventName = "resynchronised"
      previous = expected
    case .unacquired, .offGrid, .stale:
      return
    }
  } else {
    eventName = "acquired"
  }

  let calendarDateTime = snapshot.calendarDateTime
  let clockState = snapshot.clockState

  print("MSF clock ", terminator: "")
  print(eventName, terminator: "")
  print(": ", terminator: "")
  printClockComponent(calendarDateTime.year, state: clockState.year)
  print("-", terminator: "")
  printClockComponent(calendarDateTime.month, state: clockState.month)
  print("-", terminator: "")
  printClockComponent(calendarDateTime.dayOfMonth, state: clockState.dayOfMonth)
  print(" ", terminator: "")
  printClockComponent(calendarDateTime.hour, state: clockState.hour)
  print(":", terminator: "")
  printClockComponent(calendarDateTime.minute, state: clockState.minute)
  print(" ", terminator: "")
  let timeZone: StaticString =
    clockState.timeZone == .unknown
    ? "GMT/BST unknown"
    : calendarDateTime.timeZone?.abbreviation ?? ""
  print(timeZone, terminator: "")
  print("(", terminator: "")
  printClockState(clockState.timeZone)
  print(") state=", terminator: "")
  printClockState(clockState.year)
  printClockState(clockState.month)
  printClockState(clockState.dayOfMonth)
  printClockState(clockState.dayOfWeek)
  printClockState(clockState.hour)
  printClockState(clockState.minute)
  print(" missed=", terminator: "")
  print(missedMinutes, terminator: "")
  print(" contradictions=", terminator: "")
  print(contradictions, terminator: "")
  print(" parity=", terminator: "")
  print(validatedGroups, terminator: "")
  if let previous {
    print(" previous=", terminator: "")
    printClockNumber(previous.year)
    print("-", terminator: "")
    printClockNumber(previous.month)
    print("-", terminator: "")
    printClockNumber(previous.dayOfMonth)
    print(" ", terminator: "")
    printClockNumber(previous.hour)
    print(":", terminator: "")
    printClockNumber(previous.minute)
  }
  print("")
}

private func printClockComponent(_ value: Int?, state: EpistemicState) {
  if state == .unknown {
    print("??", terminator: "")
  } else {
    printClockNumber(value)
  }
}

private func printClockNumber(_ value: Int?) {
  guard let value else {
    print("??", terminator: "")
    return
  }
  if value >= 0 && value < 10 {
    print("0", terminator: "")
  }
  print(value, terminator: "")
}

private func printClockState(_ state: EpistemicState) {
  let symbol: StaticString
  switch state {
  case .unknown: symbol = "?"
  case .candidate: symbol = "c"
  case .supported: symbol = "s"
  case .confirmed: symbol = "C"
  }
  print(symbol, terminator: "")
}

func printAcquisition(_ acquisition: MSFClockAcquisition, event: MSFAcquisitionEvent) {
  switch event {
  case .ignored:
    return
  case .tooAmbiguous:
    print("MSF acquisition ambiguous: hypotheses=>capacity(", terminator: "")
    print(MSFClockAcquisition.hypothesisCapacity, terminator: "")
    print("); unseeded")
    return
  case .reset(let reason):
    print("MSF acquisition reset: ", terminator: "")
    switch reason {
    case .incompatibleEvidence:
      print("incompatible evidence", terminator: "")
    case .noLegalCalendarTime:
      print("no legal calendar time", terminator: "")
    case .offGrid(let error):
      print("off minute grid phase_error_us=", terminator: "")
      print(error, terminator: "")
    }
    print("")
    return
  case .updated:
    break
  }

  let statusName: StaticString
  switch acquisition.status {
  case .unacquired: statusName = "unacquired"
  case .ambiguous: statusName = "ambiguous"
  case .candidate: statusName = "candidate"
  case .supported: statusName = "supported"
  }
  print("MSF acquisition ", terminator: "")
  print(statusName, terminator: "")
  print(": hypotheses=", terminator: "")
  print(acquisition.hypothesisCount, terminator: "")
  print(" support=", terminator: "")
  print(acquisition.informativeFrameCount, terminator: "")
  if let calendarDateTime = acquisition.currentHypothesis {
    print(" ", terminator: "")
    printClockNumber(calendarDateTime.year)
    print("-", terminator: "")
    printClockNumber(calendarDateTime.month)
    print("-", terminator: "")
    printClockNumber(calendarDateTime.dayOfMonth)
    print(" ", terminator: "")
    printClockNumber(calendarDateTime.hour)
    print(":", terminator: "")
    printClockNumber(calendarDateTime.minute)
  }
  print("")
}

func printFrame(_ frame: MSFCompletedFrame, result: MSFFrameDecode) {
  let frameType: StaticString
  if !frame.hasOpeningMarker {
    frameType = "unknown"
  } else {
    switch frame.dataCount {
    case 58: frameType = "negative-leap"
    case 59: frameType = "normal"
    case 60: frameType = "positive-leap"
    default: frameType = "invalid-length"
    }
  }
  print("MSF frame data=", terminator: "")
  print(frame.dataCount, terminator: "")
  print(" type=", terminator: "")
  print(frameType)

  // Each valid frame fits in 64 pairs. For longer fragments, show the last 64.
  let shown = min(frame.dataCount, 64)
  print("MSF RAW: ", terminator: "")
  let openingMarker: StaticString = frame.hasOpeningMarker ? "M" : "?"
  print(openingMarker, terminator: "")
  if frame.dataCount > 64 {
    print(" ...", terminator: "")
  }
  for offset in 0..<shown {
    let bit = shown - 1 - offset
    print(" ", terminator: "")
    printFrameBit(frame.aBits, unknownBits: frame.unknownBits, at: bit)
    printFrameBit(frame.bBits, unknownBits: frame.unknownBits, at: bit)
  }
  print(" M")

  if frame.dataCount >= 43 {
    print("MSF A17-59=", terminator: "")
    for index in 0..<43 {
      printFrameBit(frame.aBits, unknownBits: frame.unknownBits, at: 42 - index)
    }
    print(" B17-59=", terminator: "")
    for index in 0..<43 {
      printFrameBit(frame.bBits, unknownBits: frame.unknownBits, at: 42 - index)
    }
    print("")
  }

  if result.decodeStatus == .valid {
    let calendarDateTime = result.calendarDateTime
    print("MSF date/time: year=", terminator: "")
    printClockNumber(calendarDateTime?.year)
    print(" month=", terminator: "")
    printClockNumber(calendarDateTime?.month)
    print(" day=", terminator: "")
    printClockNumber(calendarDateTime?.dayOfMonth)
    print(" dow=", terminator: "")
    if let dayOfWeek = calendarDateTime?.dayOfWeek {
      print(dayOfWeek, terminator: "")
    } else {
      print("?", terminator: "")
    }
    print(" ", terminator: "")
    printClockNumber(calendarDateTime?.hour)
    print(":", terminator: "")
    printClockNumber(calendarDateTime?.minute)
    print(" summerTime=", terminator: "")
    print(frame.bBits & (UInt64(1) << 1) != 0 ? 1 : 0, terminator: "")
    print(" identifier=OK parity=OK")
  } else {
    let reason: StaticString
    switch result.decodeStatus {
    case .valid: reason = "valid"
    case .insufficientData: reason = "insufficientData"
    case .invalidFrameLength: reason = "invalidFrameLength"
    case .missingData: reason = "missingData"
    case .invalidIdentifier: reason = "invalidIdentifier"
    case .parityYear: reason = "parityYear"
    case .parityMonthDay: reason = "parityMonthDay"
    case .parityDayOfWeek: reason = "parityDayOfWeek"
    case .parityHourMinute: reason = "parityHourMinute"
    case .invalidYear: reason = "invalidYear"
    case .invalidMonth: reason = "invalidMonth"
    case .invalidDayOfMonth: reason = "invalidDayOfMonth"
    case .invalidDayOfWeek: reason = "invalidDayOfWeek"
    case .invalidHour: reason = "invalidHour"
    case .invalidMinute: reason = "invalidMinute"
    }
    print("MSF frame rejected: ", terminator: "")
    print(reason)
  }
}

private func printFrameBit(_ bits: UInt64, unknownBits: UInt64, at offset: Int) {
  let mask = UInt64(1) << offset
  let symbol: StaticString =
    unknownBits & mask != 0
    ? "?"
    : bits & mask != 0 ? "1" : "0"
  print(symbol, terminator: "")
}

func drainDiagnostics() {
  var record = MSFDiagnostic()
  for _ in 0..<Int(MSF_DIAGNOSTIC_CAPACITY) {
    guard msf_diagnostics_pop(&record) else { break }
    printDiagnostic(record)
  }
  let diagnosticDropped = msf_diagnostics_take_dropped()
  if diagnosticDropped != 0 {
    print("MSF diagnostics dropped=", terminator: "")
    print(diagnosticDropped)
  }
  let frameDropped = msf_frame_take_dropped()
  if frameDropped != 0 {
    print("MSF frames dropped=", terminator: "")
    print(frameDropped)
  }
}

private func printDiagnostic(_ record: MSFDiagnostic) {
  let state: StaticString
  switch record.state {
  case 0: state = "seekingSecondStart"
  case 1: state = "awaitingFirstFall"
  case 2: state = "awaitingBStartOrNextSecond"
  case 3: state = "awaitingBFall"
  case 4: state = "awaitingNextSecondStart"
  case 5: state = "awaitingNextSecondAfterDamage"
  default: preconditionFailure("Invalid scanner state")
  }
  let resetReason: StaticString
  switch record.reset_reason {
  case 0: resetReason = "none"
  case 1: resetReason = "nonMonotonicTime"
  case 2: resetReason = "missedNextSecondStart"
  default: preconditionFailure("Invalid scanner reset reason")
  }
  let event: StaticString
  switch record.scan_event {
  case 0: event = "none"
  case 1: event = "damagedSecond"
  case 2: event = "appendedUnknownSecond"
  case 3: event = "phaseCoastStarted"
  case 4: event = "phaseRecovered"
  default: preconditionFailure("Invalid scanner event")
  }
  print("MSF ", terminator: "")
  let edge: StaticString = record.rising ? "RISE" : "FALL"
  print(edge, terminator: "")
  print(" state=", terminator: "")
  print(state, terminator: "")
  print(" prev_us=", terminator: "")
  print(record.since_previous, terminator: "")
  print(" prev_valid=", terminator: "")
  print(record.has_previous ? 1 : 0, terminator: "")
  print(" second_us=", terminator: "")
  print(record.since_second, terminator: "")
  print(" second_valid=", terminator: "")
  print(record.has_second ? 1 : 0, terminator: "")
  print(" index=", terminator: "")
  print(record.scan_index, terminator: "")
  print(" reset=", terminator: "")
  print(resetReason, terminator: "")
  print(" event=", terminator: "")
  print(event, terminator: "")
  if record.scan_event == 4 {
    print(" phase_step=", terminator: "")
    print(record.phase_step, terminator: "")
    print(" missing=", terminator: "")
    print(record.missing_slots, terminator: "")
    print(" phase_error_us=", terminator: "")
    print(record.phase_error_us, terminator: "")
  }
  print("")
}
