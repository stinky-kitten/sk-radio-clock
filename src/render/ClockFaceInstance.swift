//
//  ClockFaceInstance.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-23.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

enum ClockFaceInstance: ClockFace {
  case analogue(AnalogueClockFace)
  case analytical(AnalyticalClockFace)
  case digital(DigitalClockFace)

  #if !SWIFT_PACKAGE
    init(kind: ClockFaceKind, size: PixelSize, configuration: ClockConfiguration) {
      switch kind {
      case .analogue:
        self = .analogue(AnalogueClockFace(size: size, configuration: configuration))
      case .analytical:
        self = .analytical(AnalyticalClockFace(size: size, configuration: configuration))
      case .digital:
        self = .digital(DigitalClockFace(size: size, configuration: configuration))
      }
    }
  #endif

  func render(
    into drawingContext: inout DrawingContext,
    displaySnapshot: MSFDisplaySnapshot
  ) -> Bool {
    switch self {
    case .analogue(let face):
      return face.render(
        into: &drawingContext,
        displaySnapshot: displaySnapshot
      )
    case .analytical(let face):
      return face.render(
        into: &drawingContext,
        displaySnapshot: displaySnapshot
      )
    case .digital(let face):
      return face.render(
        into: &drawingContext,
        displaySnapshot: displaySnapshot
      )
    }
  }
}
