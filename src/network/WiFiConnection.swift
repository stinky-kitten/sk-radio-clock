//
//  WiFiConnection.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-28.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// Core 0 foreground policy. Pure values: no SDK calls, callbacks or framebuffer access.
struct WiFiConnection {
  enum Phase: Equatable {
    case waiting, connecting, associated, online, backoff
  }
  enum Failure: Equatable {
    case none, start, authentication, unavailable, link, timeout, lost
  }
  enum Action: Equatable {
    case none, connect, disconnect
  }

  static let attemptTimeoutUs: UInt64 = 30_000_000
  private(set) var phase: Phase = .waiting
  private(set) var failure: Failure = .none
  private(set) var failureCount = 0  // Saturates at the maximum-delay tier (4).
  private(set) var nextAttemptUs: UInt64 = 0
  private var startedAt: UInt64 = 0

  // Status is the SDK TCP/IP link status: -3 auth, -2 no network, -1 fail,
  // 0 down, 1 joining, 2 associated/no address, 3 up. An address is required.
  mutating func step(at now: UInt64, status: Int32, hasAddress: Bool) -> Action {
    switch phase {
    case .waiting, .backoff:
      guard now >= nextAttemptUs else { return .none }
      phase = .connecting
      failure = .none
      startedAt = now
      return .connect
    case .connecting, .associated:
      if status == 3 && hasAddress {
        phase = .online
        failureCount = 0
        return .none
      }
      if status < 0 {
        return fail(status == -3 ? .authentication : status == -2 ? .unavailable : .link, at: now)
      }
      if now &- startedAt >= Self.attemptTimeoutUs {
        return fail(.timeout, at: now)
      }
      if status == 2 || status == 3 { phase = .associated }
    case .online:
      if status != 3 || !hasAddress { return fail(.lost, at: now) }
    }
    return .none
  }

  mutating func startFailed(at now: UInt64) -> Action {
    fail(.start, at: now)
  }

  private mutating func fail(_ reason: Failure, at now: UInt64) -> Action {
    failure = reason
    phase = .backoff
    failureCount = min(failureCount + 1, 4)
    let delay: UInt64
    switch failureCount {
    case 1: delay = 5_000_000
    case 2: delay = 10_000_000
    case 3: delay = 20_000_000
    default: delay = 30_000_000
    }
    nextAttemptUs = now + delay
    return .disconnect
  }
}
