// swift-tools-version: 6.0

import Foundation
import PackageDescription

// No downloads or external commands run during manifest evaluation. SwiftPM
// resolves the experimental.3 public interface through its ordinary resolver;
// CMake alone links the firmware binary. The shared JSON holds the exact pin.
let manifestRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let pinData = try Data(
  contentsOf: manifestRoot.appendingPathComponent("Dependencies/SKLSHUB75.json"))
let pin = try JSONSerialization.jsonObject(with: pinData) as! [String: Any]
let hub75Packages: [Package.Dependency]
let hub75Targets: [Target.Dependency]
let hub75Imports: [SwiftSetting]
if let root = ProcessInfo.processInfo.environment["SKLSHUB75_ROOT"], !root.isEmpty {
  // Optional offline/development override: authentic module, no Arm autolink.
  let include = URL(fileURLWithPath: root, relativeTo: manifestRoot)
    .appendingPathComponent("include").standardizedFileURL.path
  for required in ["module.modulemap", "SKLSHUB75.apinotes", "skls_hub75/skls_hub75.h"] {
    guard FileManager.default.fileExists(atPath: include + "/" + required) else {
      fatalError(
        "SKLSHUB75_ROOT must be an unpacked binary package; missing include/\(required).")
    }
  }
  hub75Packages = []
  hub75Targets = []
  hub75Imports = [.unsafeFlags(["-I" + include])]
} else {
  hub75Packages = [
    .package(url: pin["repository_url"] as! String, exact: Version(pin["version"] as! String)!)
  ]
  hub75Targets = [.product(name: "SKLSHUB75", package: "skls-hub75-dist")]
  hub75Imports = []
}

let package = Package(
  name: "RadioClockHostTests",
  platforms: [.macOS("27.0")],
  dependencies: hub75Packages,
  targets: [
    .target(
      name: "MSFDiagnosticsTransport",
      path: "src/msf/diagnostics",
      exclude: ["MSFDiagnostics.swift"],
      sources: ["MSFDiagnostics.c"],
      publicHeadersPath: ".",
      cSettings: [
        .headerSearchPath("../../../HostSupport/MSFDiagnosticsTransport/include")
      ]
    ),
    .target(
      name: "RadioClockLogic",
      dependencies: hub75Targets,
      path: "src",
      exclude: [
        "BridgingHeader.h",
        "platform",
        "HUB75.swift",
        "Main.swift",
        "config/DefaultClockConfiguration.swift",
        "network/WiFiService.swift",
        "network/NTPService.swift",
        "network/lwipopts.h",
        "msf/diagnostics",
      ],
      sources: [
        "config/ClockConfiguration.swift",
        "config/TimeSource.swift",
        "math/FloatingPoint.swift",
        "msf/acquisition/MSFAcquisitionEvent.swift",
        "msf/acquisition/MSFAcquisitionStatus.swift",
        "msf/acquisition/MSFClockAcquisition.swift",
        "msf/acquisition/MSFSupportedAcquisition.swift",
        "msf/clock/ClockSnapshot+MSF.swift",
        "msf/clock/MSFClockEvent.swift",
        "msf/clock/MSFClockModel.swift",
        "msf/clock/MSFMinuteGrid.swift",
        "msf/display/MSFDisplaySnapshot.swift",
        "msf/epistemic/MSFEpistemicSecond.swift",
        "msf/epistemic/MSFEpistemicValue.swift",
        "msf/epistemic/MSFEvidenceFrame.swift",
        "msf/host/MSFScannerHostOutputs.swift",
        "msf/protocol/MSFChannel.swift",
        "msf/protocol/MSFCompletedFrame.swift",
        "msf/protocol/MSFExpectedFrame.swift",
        "msf/protocol/MSFField.swift",
        "msf/protocol/MSFFrameDecode.swift",
        "msf/protocol/MSFLogicalFrame.swift",
        "msf/protocol/MSFLogicalLayout.swift",
        "msf/protocol/MSFStructureAnalysis.swift",
        "msf/signal/MSFBits.swift",
        "msf/signal/MSFScan.swift",
        "msf/signal/MSFSecond.swift",
        "msf/signal/MSFTime.swift",
        "network/WiFiConfigurationValidation.swift",
        "network/WiFiConnection.swift",
        "network/NTPState.swift",
        "network/NTPUTCDiagnostic.swift",
        "render/AnalogueClockFace/AnalogueClockFace+Layout.swift",
        "render/AnalogueClockFace/AnalogueClockFace+Theme.swift",
        "render/AnalogueClockFace/AnalogueClockFace.swift",
        "render/AnalyticalClockFace/AnalyticalClockFace+Bits.swift",
        "render/AnalyticalClockFace/AnalyticalClockFace+ClockDate.swift",
        "render/AnalyticalClockFace/AnalyticalClockFace+ClockTime.swift",
        "render/AnalyticalClockFace/AnalyticalClockFace+Indicator.swift",
        "render/AnalyticalClockFace/AnalyticalClockFace+Layout.swift",
        "render/AnalyticalClockFace/AnalyticalClockFace+Theme.swift",
        "render/AnalyticalClockFace/AnalyticalClockFace+TimeZone.swift",
        "render/AnalyticalClockFace/AnalyticalClockFace+Trace.swift",
        "render/AnalyticalClockFace/AnalyticalClockFace.swift",
        "render/DigitalClockFace/DigitalClockFace.swift",
        "render/DigitalClockFace/DigitalClockFace+Layout.swift",
        "render/DigitalClockFace/DigitalClockFace+Theme.swift",
        "render/ClockFace.swift",
        "render/ClockFaceInstance.swift",
        "render/ClockFaceKind.swift",
        "render/ClockSnapshot+Formatting.swift",
        "render/ClockSnapshot+Render.swift",
        "render/ClockTheme.swift",
        "render/RenderProfile.swift",
        "render/Renderer.swift",
        "render/drawing/DrawingContext.swift",
        "render/drawing/DrawingContext+AntialiasedQuad.swift",
        "render/drawing/DrawingContext+Primitives.swift",
        "render/drawing/DrawingContext+SpanRasterTarget.swift",
        "render/drawing/DrawingContext+Text.swift",
        "render/drawing/PixelColor32.swift",
        "render/drawing/PixelCompositing.swift",
        "render/drawing/PixelFormat.swift",
        "render/drawing/SpanRasterTarget.swift",
        "render/fonts/Glyph.swift",
        "render/fonts/ClockFont.swift",
        "render/fonts/Font.swift",
        "render/fonts/MSFBitFont.swift",
        "render/fonts/PixelOperator8Font.swift",
        "render/geometry/DiskCoverage.swift",
        "render/geometry/DrawingGeometry.swift",
        "render/geometry/LineCoverage.swift",
        "render/geometry/PixelGeometry.swift",
        "render/geometry/TangentCircleCoverage.swift",
        "render/host/RenderHostTime.swift",
        "time/CalendarDateTimeComponents.swift",
        "time/CalendarDateTimeComponents+Formatting.swift",
        "time/CalendarDateTimeComponents+UTC.swift",
        "time/ClockSnapshot.swift",
        "time/ClockState.swift",
        "time/EpistemicState.swift",
        "time/TimeZone.swift",
        "time/TimeZoneConfiguration.swift",
        "time/UTCInstant.swift",
      ],
      swiftSettings: hub75Imports
    ),
    .testTarget(
      name: "RadioClockTests",
      dependencies: [.target(name: "RadioClockLogic")] + hub75Targets,
      // Compile the shared experiment helpers in the test module so they can use @testable imports.
      path: ".",
      exclude: [
        "CMakeLists.txt",
        "Config",
        "Dependencies",
        "Experiments/Circles/CircleRenderExperiment.swift",
        "HostSupport",
        "LICENSES",
        "README.md",
        "Tests/MSFTransportTests",
        "cmake",
        "docs",
        "pico_sdk_import.cmake",
        "src",
        "tools",
      ] + ["build"].filter { FileManager.default.fileExists(atPath: manifestRoot.appendingPathComponent($0).path) },
      sources: ["Tests/RadioClockTests", "Experiments/Circles"],
      swiftSettings: hub75Imports
    ),
    .testTarget(
      name: "MSFTransportTests",
      dependencies: ["MSFDiagnosticsTransport"]
    ),
  ]
)
