//
//  MSFDisplaySnapshot.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-07.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// Immutable, allocation-free display view. Bit 0 is the oldest pulse column.
// Both level bits set in a column means activity within that 100 ms interval.
struct MSFDisplaySnapshot {
  static let binCount = 60
  static let binDuration: MSFTime = 100_000

  let clockSnapshot: ClockSnapshot
  let secondPhaseBin: Int?  // 0...9

  // Trace bins retain their quantized timestamp; clock movement uses sampleTime.
  let sampleTime: MSFTime
  let minuteMarkerTime: MSFTime?
  let timestamp: MSFTime
  let signalHigh: Bool
  let highBins: UInt64
  let lowBins: UInt64

  // Six low bits, oldest slot at index 0.
  // Presence and A/B validity are independent.
  static let secondCount = 6
  let seconds: InlineArray<6, MSFDisplaySecond>

  init(
    clockSnapshot: ClockSnapshot,
    secondPhaseBin: Int?,
    timestamp: MSFTime, signalHigh: Bool, highBins: UInt64, lowBins: UInt64,
    seconds: InlineArray<6, MSFDisplaySecond> = .init(repeating: .absent),
    sampleTime: MSFTime? = nil, minuteMarkerTime: MSFTime? = nil
  ) {
    self.clockSnapshot = clockSnapshot
    self.secondPhaseBin = secondPhaseBin

    self.sampleTime = sampleTime ?? timestamp
    self.minuteMarkerTime = minuteMarkerTime
    self.timestamp = timestamp
    self.signalHigh = signalHigh
    self.highBins = highBins
    self.lowBins = lowBins

    self.seconds = seconds
  }

  init(raw: MSFDisplaySnapshot, clockSnapshot: ClockSnapshot) {
    self.init(
      clockSnapshot: clockSnapshot.withSecondTiming(at: raw.sampleTime, minuteMarkerTime: raw.minuteMarkerTime),
      secondPhaseBin: raw.secondPhaseBin,
      timestamp: raw.timestamp, signalHigh: raw.signalHigh, highBins: raw.highBins,
      lowBins: raw.lowBins,
      seconds: raw.seconds, sampleTime: raw.sampleTime, minuteMarkerTime: raw.minuteMarkerTime)
  }
}

enum MSFDisplaySecond: Equatable {
  case absent
  case unknown
  case decoded(MSFSecond)
}
