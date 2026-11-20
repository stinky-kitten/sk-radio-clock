// SwiftPM-only output capture for the production scanner. Firmware uses the C
// implementations; this file is absent from its explicit CMake source list.
#if SWIFT_PACKAGE
  import Synchronization

  struct MSFScannerHostDiagnostic: Equatable {
    let rising: Bool
    let state: UInt8
    let sincePrevious: UInt64?
    let sinceSecond: UInt64?
    let scanIndex: UInt32
    let resetReason: UInt8
    let event: UInt8
    let phaseStep: UInt8
    let missingSlots: UInt8
    let phaseError: Int32
  }

  enum MSFScannerHostOutputs {
    // The scanner suite is serialized and resets capture for each case.
    // The mutex protects individual accesses, not interleaved test sessions.
    fileprivate static let storage = Mutex(
      (diagnostics: [MSFScannerHostDiagnostic](), frames: [MSFCompletedFrame]()))

    static func reset() {
      storage.withLock { $0 = ([], []) }
    }

    static var diagnostics: [MSFScannerHostDiagnostic] {
      storage.withLock { $0.diagnostics }
    }

    static var frames: [MSFCompletedFrame] {
      storage.withLock { $0.frames }
    }
  }

  func msf_diagnostics_enqueue(
    _ rising: Bool, _ state: UInt8, _ hasPrevious: Bool, _ previous: UInt64,
    _ hasSecond: Bool, _ second: UInt64, _ index: UInt32, _ reason: UInt8,
    _ event: UInt8, _ phaseStep: UInt8, _ missingSlots: UInt8, _ phaseError: Int32
  ) {
    let record = MSFScannerHostDiagnostic(
      rising: rising, state: state,
      sincePrevious: hasPrevious ? previous : nil,
      sinceSecond: hasSecond ? second : nil,
      scanIndex: index, resetReason: reason, event: event,
      phaseStep: phaseStep, missingSlots: missingSlots, phaseError: phaseError)
    MSFScannerHostOutputs.storage.withLock { $0.diagnostics.append(record) }
  }

  func msf_frame_publish(
    _ a: UInt64, _ b: UInt64, _ unknown: UInt64,
    _ count: UInt32, _ opening: Bool, _ closingMarkerTime: UInt64
  ) {
    let frame = MSFCompletedFrame(
      aBits: a, bBits: b, unknownBits: unknown,
      dataCount: Int(count), hasOpeningMarker: opening,
      closingMarkerTime: closingMarkerTime)
    MSFScannerHostOutputs.storage.withLock { $0.frames.append(frame) }
  }
#endif
