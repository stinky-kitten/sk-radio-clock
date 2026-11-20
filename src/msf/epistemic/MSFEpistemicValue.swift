//
//  MSFEpistemicValue.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-05.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct MSFEpistemicValue<Value> where Value: Equatable {

  private(set) var value: Value?
  private(set) var confidence: UInt8

  init() {
    value = nil
    confidence = 0
  }

  var state: EpistemicState {

    switch confidence {
    case 0:
      return .unknown
    case 1...MSFConfidence.candidateMaximum:
      return .candidate
    case (MSFConfidence.candidateMaximum + 1)...MSFConfidence.supportedMaximum:
      return .supported
    default:
      return .confirmed
    }
  }

  mutating func age() {
    guard confidence > 0 else {
      return
    }

    confidence -= 1

    if confidence == 0 {
      value = nil
    }
  }

  // Only a temporal model that has advanced the same semantic value should
  // call this. Projection does not create evidence or alter its strength.
  mutating func transitionExpectedValue(to expected: Value) {
    guard confidence > 0 else { return }
    value = expected
  }

  // Only structurally validated parity or a complete confirmed frame may
  // establish maximum confidence without ordinary one-point reinforcement.
  mutating func confirmValidatedValue(_ confirmed: Value) {
    value = confirmed
    confidence = MSFConfidence.maximum
  }

  // The caller must establish that this observation concerns the same
  // semantic value. A differing value is reported without changing belief.
  @discardableResult
  mutating func observeSameLogicalValue(_ observed: Value?) -> MSFEpistemicUpdate<Value> {
    guard let observed else {
      age()
      return .aged
    }
    guard let current = value else {
      value = observed
      confidence = 1
      return .seeded
    }
    guard current == observed else {
      return .contradiction(existing: current, observed: observed)
    }
    if confidence < MSFConfidence.maximum { confidence += 1 }
    return .reinforced
  }
}

enum MSFEpistemicUpdate<Value>: Equatable where Value: Equatable {
  case aged
  case seeded
  case reinforced
  case contradiction(existing: Value, observed: Value)
}

enum MSFConfidence {
  static let candidateMaximum: UInt8 = 10
  static let supportedMaximum: UInt8 = 20
  static let maximum: UInt8 = 30
}

extension MSFEpistemicValue: Equatable {
  static func == (lhs: MSFEpistemicValue<Value>, rhs: MSFEpistemicValue<Value>) -> Bool {
    return lhs.value == rhs.value && lhs.confidence == rhs.confidence
  }
}
