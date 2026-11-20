//
//  MSFAcquisitionEvent.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-06.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

enum MSFAcquisitionEvent: Equatable {
  case updated
  case tooAmbiguous
  case reset(MSFAcquisitionReset)
  case ignored(MSFAcquisitionIgnore)
}

enum MSFAcquisitionReset: Equatable {
  case incompatibleEvidence
  case noLegalCalendarTime
  case offGrid(phaseErrorUs: Int64)
}

enum MSFAcquisitionIgnore: Equatable {
  case uninformative, invalidIdentifier, invalidFrameLength, insufficientData
  case staleMarker, confirmedFrame
}
