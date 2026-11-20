//
//  MSFClockReporter.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-29.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct MSFClockReporter {
  private var lastReportedMinuteIndex: UInt64?

  mutating func report(
    event: MSFClockEvent,
    clock: MSFClockModel,
    at now: MSFTime
  ) {
    switch event {
    case .acquired, .acquiredFromPartial, .updated,
      .corroborated, .resynchronised:
      guard let snapshot = clock.currentSnapshot(at: now),
        let index = clock.projectedMinuteIndex(at: now)
      else {
        return
      }

      printClock(snapshot, event: event)
      lastReportedMinuteIndex = index

    case .unacquired, .offGrid, .stale:
      break
    }
  }

  mutating func reportPredictedMinute(
    clock: MSFClockModel,
    at now: MSFTime
  ) {
    guard let index = clock.projectedMinuteIndex(at: now),
      index != lastReportedMinuteIndex,
      let snapshot = clock.currentSnapshot(at: now)
    else {
      return
    }

    printClock(snapshot, event: nil, predicted: true)
    lastReportedMinuteIndex = index
  }
}
