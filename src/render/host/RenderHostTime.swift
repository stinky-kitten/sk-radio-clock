//
//  RenderHostTime.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-11-03.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// SwiftPM-only link boundary, absent from the firmware's explicit source list.
#if SWIFT_PACKAGE
  import Synchronization

  enum RenderHostTime {
    // Each synchronous test/render session owns its script. Task-local
    // scope isolates concurrent tests (independent .serialized suites do
    // not). Exiting withTimestamps restores the previous clock, or none.
    // Child tasks inherit the session; do not share one session between
    // concurrent render calls. The mutex protects reads, not their order.
    @TaskLocal private static var script: Script?

    static func withTimestamps<Result>(_ timestamps: [UInt64], _ body: () -> Result) -> Result {
      $script.withValue(Script(timestamps)) { body() }
    }

    static var readCount: Int {
      guard let script else { preconditionFailure("No host render clock session") }
      return script.state.withLock { $0.index }
    }

    fileprivate static func next() -> UInt64 {
      guard let script else { preconditionFailure("No host render clock session") }
      return script.state.withLock { state in
        precondition(state.index < state.timestamps.count, "Host render clock script exhausted")
        defer { state.index += 1 }
        return state.timestamps[state.index]
      }
    }

    private final class Script: Sendable {
      let state: Mutex<(timestamps: [UInt64], index: Int)>

      init(_ timestamps: [UInt64]) {
        state = Mutex((timestamps, 0))
      }
    }
  }

  func time_us_64() -> UInt64 {
    RenderHostTime.next()
  }
#endif
