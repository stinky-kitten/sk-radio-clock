//
//  MSFScan.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-09-25.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

private let msfSecondPhaseTolerance: MSFTime = 40_000
// A recovered rise may be at most six grid steps ahead: five unseen slots.
private let maxPhaseCoastSeconds: UInt64 = 5

struct MSFScan {

  enum Polarity {
    case carrierPresentLow
    case carrierPresentHigh
  }

  private let polarity: Polarity

  enum SignalChange {
    case rising
    case falling
  }

  private enum ScanningState: UInt8 {
    case seekingSecondStart
    case awaitingFirstFall
    case awaitingBStartOrNextSecond
    case awaitingBFall
    case awaitingNextSecondStart
    case awaitingNextSecondAfterDamage
  }

  private enum ResetReason: UInt8 {
    case none
    case nonMonotonicTime
    case missedNextSecondStart
  }

  private enum ScanEvent: UInt8 {
    case none
    case damagedSecond
    case appendedUnknownSecond
    case phaseCoastStarted
    case phaseRecovered
  }

  private var scan: InlineArray<100, MSFSecond?> = .init(repeating: nil)
  private var lastSignalChange: SignalChange? = nil
  private var currentIndex: Int = 0
  private var lastEdgeTime: MSFTime?
  private var secondPulseStartTime: MSFTime?
  private var previousSecondStartTime: MSFTime?
  private var earlierSecondStartTime: MSFTime?
  private var recoveryPhaseAnchor: (time: MSFTime, index: UInt64)?
  private var secondPhaseIndex: UInt64 = 0
  private var phaseCoasting = false
  private var scanningState: ScanningState = .seekingSecondStart
  private var minutePulseStartTime: MSFTime?
  private var ordinarySlotsSinceMarker: Int?
  private var openingMarkerTrusted = false

  // Timestamped 20 ms activity samples, independent of decoded seconds.
  // Coalescing records both observed levels, so even arbitrarily dense noise
  // remains visible without overflowing an edge queue. One extra slot holds
  // the current partial sample; the preceding 300 samples span six seconds.
  private static let rawSampleDuration: MSFTime = 20_000
  private static let rawSampleCount = 301
  private var rawSamples: InlineArray<301, UInt64> = .init(repeating: 0)
  private var rawSignalHigh = false
  private var rawSignalKnown = false
  private var rawLastTime: MSFTime?

  // Display metadata only: decoder decisions and scan contents are unchanged.
  // Eight observed starts cover six seconds plus the window boundaries.
  private struct DisplaySecond {
    var gridIndex: UInt64? = nil
    var value: MSFSecond? = nil
    var closed = false
  }
  private var displaySeconds: InlineArray<8, DisplaySecond> = .init(repeating: .init())
  private var nextDisplaySecond = 0

  init(polarity: Polarity = .carrierPresentLow) {
    self.polarity = polarity
  }

  // Observe the physical GPIO level without feeding a synthetic decoder edge.
  mutating func observeRawSignal(high: Bool, at now: MSFTime) {
    recordRawSignal(high: high, at: now)
  }

  // Inout access borrows the inline storage instead of copying it in Debug.
  // Producing the snapshot does not change the captured history.
  mutating func displaySnapshot(at now: MSFTime) -> MSFDisplaySnapshot {
    let samplesPerBin = Int(MSFDisplaySnapshot.binDuration / Self.rawSampleDuration)
    let endSample = now / Self.rawSampleDuration
    var highBins: UInt64 = 0
    var lowBins: UInt64 = 0
    var high = rawSignalHigh
    var known = rawSignalKnown
    let samples = rawSamples.mutableSpan

    // Exclude the current incomplete 20 ms sample from the trace, restoring
    // its starting level. The indicator still reports the latest level.
    let partial = samples[Int(endSample % UInt64(Self.rawSampleCount))]
    if partial >> 5 == endSample + 1 {
      high = partial & 8 != 0
      known = partial & 16 != 0
    }

    for age in 0..<(MSFDisplaySnapshot.binCount * samplesPerBin) {
      guard UInt64(age) < endSample else { break }
      let sampleIndex = endSample - 1 - UInt64(age)
      let sample = samples[Int(sampleIndex % UInt64(Self.rawSampleCount))]
      let bit = UInt64(1) << (MSFDisplaySnapshot.binCount - 1 - age / samplesPerBin)
      if sample >> 5 == sampleIndex + 1 {
        if sample & 2 != 0 { highBins |= bit }
        if sample & 1 != 0 { lowBins |= bit }
        high = sample & 8 != 0
        known = sample & 16 != 0
      } else if known {
        if high { highBins |= bit } else { lowBins |= bit }
      }
    }
    let timestamp = endSample * Self.rawSampleDuration
    var displaySeconds: InlineArray<6, MSFDisplaySecond> =
      .init(repeating: .absent)

    let phase = phaseSecond(at: timestamp)
    if let currentGridIndex = phase?.index {
      let seconds = self.displaySeconds.mutableSpan

      // Visit oldest to newest so the newest observation wins if two
      // records ever map to the same grid position.
      for offset in 0..<8 {
        let second = seconds[(nextDisplaySecond + offset) % 8]

        guard second.closed,
          let gridIndex = second.gridIndex,
          gridIndex < currentGridIndex
        else {
          continue
        }

        let secondsAgo = currentGridIndex - gridIndex

        guard secondsAgo >= 1 && secondsAgo <= 6 else {
          continue
        }

        let slot = 6 - Int(secondsAgo)

        if let value = second.value {
          displaySeconds[slot] = .decoded(value)
        } else {
          displaySeconds[slot] = .unknown
        }
      }
    }
    return MSFDisplaySnapshot(
      clockSnapshot: ClockSnapshot.unknown,
      secondPhaseBin: phase.map { Int($0.elapsedInSecond / MSFDisplaySnapshot.binDuration) },
      timestamp: timestamp,
      signalHigh: rawSignalHigh,
      highBins: highBins,
      lowBins: lowBins,
      seconds: displaySeconds,
      sampleTime: now, minuteMarkerTime: minutePulseStartTime
    )
  }

  private mutating func recordRawSignal(high: Bool, at now: MSFTime) {
    if let rawLastTime, now < rawLastTime {
      var samples = rawSamples.mutableSpan
      for index in 0..<Self.rawSampleCount { samples[index] = 0 }
      rawSignalKnown = false
      var seconds = displaySeconds.mutableSpan
      for index in 0..<8 { seconds[index] = .init() }
      nextDisplaySecond = 0
    }
    let sampleIndex = now / Self.rawSampleDuration
    let index = Int(sampleIndex % UInt64(Self.rawSampleCount))
    // Bits 0/1 independently flag LOW/HIGH observed during the interval;
    // both may be set when a transition occurs. Bit 2 is unused. Bit 3
    // records a HIGH starting level; bit 4 says that starting level was known.
    // Bits 5...63 store sampleIndex + 1, identifying the sampling interval
    // across ring-buffer reuse and reserving zero for an empty slot.
    let tag = (sampleIndex + 1) << 5
    var samples = rawSamples.mutableSpan
    var sample = samples[index]
    if sample >> 5 != sampleIndex + 1 {
      sample = tag
      if rawSignalKnown {
        sample |= 16 | (rawSignalHigh ? 8 | 2 : 1)
      }
    }
    sample |= high ? 2 : 1
    samples[index] = sample
    rawSignalHigh = high
    rawSignalKnown = true
    rawLastTime = now
  }

  var recordedCount: Int { currentIndex }

  func recordedSecond(at index: Int) -> MSFSecond? {
    guard index >= 0 && index < currentIndex else { return nil }
    return scan[index]
  }

  mutating func receiveSignalChange(_ physicalChange: SignalChange, at now: MSFTime) {
    recordRawSignal(high: physicalChange == .rising, at: now)
    // Keep the state machine's active-low edge convention; raw history and
    // diagnostic RISE/FALL labels continue to describe the physical GPIO.
    let change: SignalChange =
      polarity == .carrierPresentLow
      ? physicalChange : (physicalChange == .rising ? .falling : .rising)
    let stateBefore = scanningState
    let indexBefore = currentIndex
    let previousChange = lastSignalChange
    var sincePrevious: MSFTime?
    if let lastEdgeTime, now >= lastEdgeTime {
      sincePrevious = now - lastEdgeTime
    }
    var sinceSecond: MSFTime?
    if let secondPulseStartTime, now >= secondPulseStartTime {
      sinceSecond = now - secondPulseStartTime
    }
    var resetReason: ResetReason = .none
    var scanEvent: ScanEvent = .none
    var phaseStep: UInt8 = 0
    var missingSlots: UInt8 = 0
    var phaseError: Int32 = 0

    let phase = phasePosition(at: now)

    if let lastEdgeTime, now < lastEdgeTime {
      resetReason = .nonMonotonicTime
    } else if scanningState != .seekingSecondStart, !phaseCoasting,
      change == .rising, let sinceSecond,
      sinceSecond.isWithinTolerance(of: 1_000_000)
    {
      missingSlots = finishCurrentSecond(directBoundary: true)
      if missingSlots != 0 { scanEvent = .appendedUnknownSecond }
      startSecond(at: now, gridIndex: secondPhaseIndex + 1)
    } else if scanningState != .seekingSecondStart,
      change == .rising, let phase,
      phase.index > secondPhaseIndex,
      phase.index - secondPhaseIndex <= maxPhaseCoastSeconds + 1,
      phase.error >= -Int32(msfSecondPhaseTolerance),
      phase.error <= Int32(msfSecondPhaseTolerance)
    {
      let step = phase.index - secondPhaseIndex
      missingSlots = finishCurrentSecond(directBoundary: step == 1)
      for _ in 1..<step {
        appendScanEntry(nil)
        missingSlots += 1
      }
      startSecond(at: now, gridIndex: phase.index)
      scanEvent = .phaseRecovered
      phaseStep = UInt8(step)
      phaseError = phase.error
    } else if scanningState != .seekingSecondStart,
      let phase, isPhaseRecoveryExpired(for: phase)
    {
      resetReason = .missedNextSecondStart
    } else if scanningState != .seekingSecondStart,
      let sinceSecond, sinceSecond > 1_030_000
    {
      if !phaseCoasting {
        phaseCoasting = true
        scanEvent = .phaseCoastStarted
      }
    } else {
      switch scanningState {
      case .seekingSecondStart:
        if change == .rising, previousChange == .falling,
          let sincePrevious, sincePrevious > 480_000 && sincePrevious <= 1_200_000
        {
          establishPhase(at: now)
        }

      case .awaitingFirstFall:
        if change != .falling {
          damageSecond()
          scanEvent = .damagedSecond
        } else if let sinceSecond, sinceSecond.isWithinTolerance(of: 100_000) {
          scanningState = .awaitingBStartOrNextSecond
        } else if let sinceSecond, sinceSecond.isWithinTolerance(of: 200_000) {
          appendScanEntry(.bits(MSFBits(a: true, b: false)))
          scanningState = .awaitingNextSecondStart
        } else if let sinceSecond, sinceSecond.isWithinTolerance(of: 300_000) {
          appendScanEntry(.bits(MSFBits(a: true, b: true)))
          scanningState = .awaitingNextSecondStart
        } else if let sinceSecond, sinceSecond.isWithinTolerance(of: 500_000) {
          appendScanEntry(.minuteMarker)
          minutePulseStartTime = secondPulseStartTime
          refreshRecoveryPhaseAtMarker()
          scanningState = .awaitingNextSecondStart
          if let closingMarkerTime = secondPulseStartTime,
            let frame = completedFrameAtMarker(closingMarkerTime: closingMarkerTime)
          {
            msf_frame_publish(
              frame.aBits, frame.bBits, frame.unknownBits,
              UInt32(frame.dataCount), frame.hasOpeningMarker,
              frame.closingMarkerTime)
          }
          openingMarkerTrusted = true
        } else {
          damageSecond()
          scanEvent = .damagedSecond
        }

      case .awaitingBStartOrNextSecond:
        if change != .rising {
          damageSecond()
          scanEvent = .damagedSecond
        } else if let sinceSecond, sinceSecond.isWithinTolerance(of: 200_000) {
          scanningState = .awaitingBFall
        } else {
          damageSecond()
          scanEvent = .damagedSecond
        }

      case .awaitingBFall:
        if change != .falling {
          damageSecond()
          scanEvent = .damagedSecond
        } else if let sinceSecond, sinceSecond.isWithinTolerance(of: 300_000) {
          appendScanEntry(.bits(MSFBits(a: false, b: true)))
          scanningState = .awaitingNextSecondStart
        } else {
          damageSecond()
          scanEvent = .damagedSecond
        }

      case .awaitingNextSecondStart:
        // A completed pair or validated marker stays known despite
        // subsequent short noise; only the 1s rise starts a new second.
        break

      case .awaitingNextSecondAfterDamage:
        // Further intra-second edges cannot restore the lost A/B pair.
        break
      }
    }

    // Queue the state and index from before this edge, including reset-causing edges.
    msf_diagnostics_enqueue(
      physicalChange == .rising, stateBefore.rawValue,
      sincePrevious != nil, sincePrevious ?? 0,
      sinceSecond != nil, sinceSecond ?? 0,
      UInt32(indexBefore), resetReason.rawValue, scanEvent.rawValue,
      phaseStep, missingSlots, phaseError
    )
    if resetReason != .none {
      reset()
      // A long carrier-on interval can make this same rising edge a new candidate
      // second start, even though the previous scan was discarded.
      if change == .rising, previousChange == .falling,
        let sincePrevious, sincePrevious > 480_000 && sincePrevious <= 1_200_000
      {
        establishPhase(at: now)
      }
    }
    lastSignalChange = change
    lastEdgeTime = now
  }

  mutating private func establishPhase(at now: MSFTime) {
    recoveryPhaseAnchor = (now, 0)
    startSecond(at: now, gridIndex: 0)
  }

  mutating private func startSecond(at now: MSFTime, gridIndex: UInt64) {
    if gridIndex == secondPhaseIndex + 1 {
      earlierSecondStartTime = previousSecondStartTime
      previousSecondStartTime = secondPulseStartTime
    } else {
      earlierSecondStartTime = nil
      previousSecondStartTime = nil
    }
    secondPulseStartTime = now
    secondPhaseIndex = gridIndex
    phaseCoasting = false
    scanningState = .awaitingFirstFall
    var seconds = displaySeconds.mutableSpan
    seconds[nextDisplaySecond] = DisplaySecond(gridIndex: gridIndex)
    nextDisplaySecond = (nextDisplaySecond + 1) % 8
  }

  private mutating func refreshRecoveryPhaseAtMarker() {
    guard let marker = secondPulseStartTime,
      let previous = previousSecondStartTime,
      let earlier = earlierSecondStartTime
    else { return }

    // Compare three consecutive accepted starts at the earliest slot. Using
    // their median keeps a single jittered start from setting the grid, and
    // retaining that slot's index leaves all recorded positions intact.
    let projectedMarker = marker - 2_000_000
    let projectedPrevious = previous - 1_000_000
    let lower = min(earlier, projectedPrevious)
    let upper = max(earlier, projectedPrevious)
    let median = min(max(projectedMarker, lower), upper)
    recoveryPhaseAnchor = (median, secondPhaseIndex - 2)
  }

  // Recovery rounds to the nearest slot. The display uses the containing slot
  // on the same grid, with time within the second for its phase bin.
  private func phasePosition(at now: MSFTime) -> (index: UInt64, error: Int32)? {
    guard let phase = phaseSecond(at: now) else { return nil }
    if phase.elapsedInSecond > 500_000 {
      return (phase.index + 1, Int32(phase.elapsedInSecond) - 1_000_000)
    }
    return (phase.index, Int32(phase.elapsedInSecond))
  }

  private func phaseSecond(at now: MSFTime) -> (index: UInt64, elapsedInSecond: MSFTime)? {
    guard let anchor = recoveryPhaseAnchor, now >= anchor.time else { return nil }
    let elapsed = now - anchor.time
    return (anchor.index + elapsed / 1_000_000, elapsed % 1_000_000)
  }

  private func isPhaseRecoveryExpired(for phase: (index: UInt64, error: Int32)) -> Bool {
    let lastRecoverable = secondPhaseIndex + maxPhaseCoastSeconds + 1
    return phase.index > lastRecoverable
      || (phase.index == lastRecoverable && phase.error > Int32(msfSecondPhaseTolerance))
  }

  private mutating func finishCurrentSecond(directBoundary: Bool) -> UInt8 {
    let missingSlots: UInt8

    switch scanningState {
    case .awaitingNextSecondStart:
      // The pair or marker was inserted when its fall was validated.
      missingSlots = 0

    case .awaitingBStartOrNextSecond where directBoundary:
      appendScanEntry(.bits(MSFBits(a: false, b: false)))
      missingSlots = 0

    case .awaitingFirstFall,
      .awaitingBStartOrNextSecond,
      .awaitingBFall,
      .awaitingNextSecondAfterDamage:
      appendScanEntry(nil)
      missingSlots = 1

    case .seekingSecondStart:
      return 0
    }

    let index = (nextDisplaySecond + 7) % 8
    var seconds = displaySeconds.mutableSpan

    if seconds[index].gridIndex == secondPhaseIndex {
      seconds[index].closed = true
    }

    return missingSlots
  }

  private mutating func damageSecond() {
    scanningState = .awaitingNextSecondAfterDamage
  }

  private mutating func reset() {
    scan = .init(repeating: nil)
    currentIndex = 0
    secondPulseStartTime = nil
    previousSecondStartTime = nil
    earlierSecondStartTime = nil
    recoveryPhaseAnchor = nil
    secondPhaseIndex = 0
    phaseCoasting = false
    scanningState = .seekingSecondStart
    minutePulseStartTime = nil
    ordinarySlotsSinceMarker = nil
    openingMarkerTrusted = false

    var seconds = displaySeconds.mutableSpan
    for index in 0..<8 {
      seconds[index] = .init()
    }
    nextDisplaySecond = 0
  }

  private mutating func appendScanEntry(_ value: MSFSecond?) {
    // Observe only an already accepted pair. Unknown insertions during
    // phase recovery must not overwrite an earlier completed pair.
    if let value {
      let index = (nextDisplaySecond + 7) % 8
      var seconds = displaySeconds.mutableSpan

      if seconds[index].gridIndex == secondPhaseIndex {
        seconds[index].value = value
      }
    }
    if value == nil, let ordinarySlotsSinceMarker,
      ordinarySlotsSinceMarker >= 58
    {
      // An unseen slot could have been the next marker (negative leap
      // minutes can close after 58 ordinary positions).
      openingMarkerTrusted = false
      minutePulseStartTime = nil
    }
    if currentIndex == scan.count {
      for index in 0..<(scan.count - 1) {
        scan[index] = scan[index + 1]
      }
      currentIndex -= 1
    }
    scan[currentIndex] = value
    currentIndex += 1
    if value == .minuteMarker {
      ordinarySlotsSinceMarker = 0
    } else if let count = ordinarySlotsSinceMarker {
      ordinarySlotsSinceMarker = count + 1
    }
  }

  private func completedFrameAtMarker(closingMarkerTime: MSFTime) -> MSFCompletedFrame? {
    guard currentIndex > 1 else { return nil }
    var aBits: UInt64 = 0
    var bBits: UInt64 = 0
    var unknownBits: UInt64 = 0
    var dataCount = 0
    var hasOpeningMarker = false
    var index = currentIndex - 2
    scanLoop: while index >= 0 {
      switch scan[index] {
      case .some(.minuteMarker):
        hasOpeningMarker = openingMarkerTrusted
        break scanLoop
      case .some(.bits(let bits)):
        // Bit zero is the last data pair before the closing marker.
        if dataCount < 64 {
          if bits.a { aBits |= UInt64(1) << dataCount }
          if bits.b { bBits |= UInt64(1) << dataCount }
        }
        dataCount += 1
      case .none:
        if dataCount < 64 { unknownBits |= UInt64(1) << dataCount }
        dataCount += 1
      }
      index -= 1
    }
    // The first marker only establishes an opening; a later empty frame is
    // still worth reporting as insufficient data.
    guard dataCount > 0 || hasOpeningMarker else { return nil }
    return MSFCompletedFrame(
      aBits: aBits, bBits: bBits, unknownBits: unknownBits,
      dataCount: dataCount, hasOpeningMarker: hasOpeningMarker,
      closingMarkerTime: closingMarkerTime)
  }
}
