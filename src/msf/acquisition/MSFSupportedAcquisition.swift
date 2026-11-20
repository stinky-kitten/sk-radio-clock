//
//  MSFSupportedAcquisition.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-06.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct MSFSupportedAcquisition {
  let anchorCalendarDateTime: CalendarDateTimeComponents
  let anchorMarkerTime: UInt64
  let currentCalendarDateTime: CalendarDateTimeComponents
  let minuteIndex: UInt64
  let lastMarkerTime: UInt64
  let evidence: MSFEvidenceFrame
  let summerTime: Bool?

  init(
    anchorCalendarDateTime: CalendarDateTimeComponents, anchorMarkerTime: UInt64,
    currentCalendarDateTime: CalendarDateTimeComponents, minuteIndex: UInt64,
    lastMarkerTime: UInt64, evidence: MSFEvidenceFrame, summerTime: Bool?
  ) {
    self.anchorCalendarDateTime = anchorCalendarDateTime
    self.anchorMarkerTime = anchorMarkerTime
    self.currentCalendarDateTime = currentCalendarDateTime
    self.minuteIndex = minuteIndex
    self.lastMarkerTime = lastMarkerTime
    self.evidence = evidence
    self.summerTime = summerTime
  }
}
