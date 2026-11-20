//
//  RenderProfile.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

#if SK_RADIO_CLOCK_RENDER_PROFILE || SWIFT_PACKAGE
  struct RenderProfile {
    struct Statistics {
      var received: UInt64 = 0
      var samples: UInt64 = 0
      var completed: UInt64 = 0
      var rejected: UInt64 = 0
      var durationLatestUs: UInt64 = 0
      var durationMinUs: UInt64 = 0
      var durationMaxUs: UInt64 = 0
      var durationTotalUs: UInt64 = 0
      var slackLatestUs: Int64 = 0
      var slackMinUs: Int64 = 0
      var slackMaxUs: Int64 = 0
      var lateStarts: UInt64 = 0
      var completedLate: UInt64 = 0

      var durationAverageUs: UInt64 {
        samples == 0 ? 0 : durationTotalUs / samples
      }
    }

    private var storedStatistics: Statistics
    private var lastReportedAt: UInt64

    init(statistics: Statistics = Statistics(), lastReportedAt: UInt64 = 0) {
      storedStatistics = statistics
      self.lastReportedAt = lastReportedAt
    }

    var statistics: Statistics { storedStatistics }

    mutating func recordReceived() {
      storedStatistics.received &+= 1
    }

    mutating func recordRender(
      startedAt: UInt64, finishedAt: UInt64, deadline: UInt64, completed: Bool
    ) {
      let duration = finishedAt &- startedAt
      let magnitude = deadline >= startedAt ? deadline - startedAt : startedAt - deadline
      let bounded = Int64(min(magnitude, UInt64(Int64.max)))
      let slack = deadline >= startedAt ? bounded : -bounded

      storedStatistics.durationLatestUs = duration
      storedStatistics.slackLatestUs = slack
      if storedStatistics.samples == 0 || duration < storedStatistics.durationMinUs {
        storedStatistics.durationMinUs = duration
      }
      // Unlike the other extrema, the maximum survives sample-counter wrap.
      if duration > storedStatistics.durationMaxUs {
        storedStatistics.durationMaxUs = duration
      }
      if storedStatistics.samples == 0 || slack < storedStatistics.slackMinUs {
        storedStatistics.slackMinUs = slack
      }
      if storedStatistics.samples == 0 || slack > storedStatistics.slackMaxUs {
        storedStatistics.slackMaxUs = slack
      }
      storedStatistics.samples &+= 1
      storedStatistics.durationTotalUs &+= duration
      if startedAt >= deadline {
        storedStatistics.lateStarts &+= 1
      }
      if completed {
        storedStatistics.completed &+= 1
        if finishedAt >= deadline {
          storedStatistics.completedLate &+= 1
        }
      } else {
        storedStatistics.rejected &+= 1
      }
    }

    mutating func takeReport(at now: UInt64) -> Statistics? {
      guard now &- lastReportedAt >= 1_000_000 else { return nil }
      lastReportedAt = now
      return storedStatistics
    }
  }

  func printRenderProfile(_ statistics: RenderProfile.Statistics) {
    print("RENDER req=", terminator: "")
    print(statistics.received, terminator: "")
    print(" done=", terminator: "")
    print(statistics.completed, terminator: "")
    print(" reject=", terminator: "")
    print(statistics.rejected, terminator: "")
    print(" dur_us=", terminator: "")
    print(statistics.durationLatestUs, terminator: "")
    print("/", terminator: "")
    print(statistics.durationMinUs, terminator: "")
    print("/", terminator: "")
    print(statistics.durationMaxUs, terminator: "")
    print("/", terminator: "")
    print(statistics.durationAverageUs, terminator: "")
    print(" slack_us=", terminator: "")
    print(statistics.slackLatestUs, terminator: "")
    print("/", terminator: "")
    print(statistics.slackMinUs, terminator: "")
    print("/", terminator: "")
    print(statistics.slackMaxUs, terminator: "")
    print(" late_start=", terminator: "")
    print(statistics.lateStarts, terminator: "")
    print(" late_done=", terminator: "")
    print(statistics.completedLate)
  }
#endif
