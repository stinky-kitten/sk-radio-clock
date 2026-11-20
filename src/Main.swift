//
//  Main.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-09-24.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import SKLSHUB75

// Foreground initializes the scanner before enabling GPIO IRQs; the callback then
// owns updates, and foreground snapshots are taken with GPIO IRQs disabled.
private var msfScan = MSFScan(polarity: .carrierPresentLow)

#if SK_RADIO_CLOCK_CYW43_LED
  // The leading 1 marks up to 31 queued raw levels, oldest first.
  // If full, replace the newest entry so the LED still reaches the latest level.
  private var pendingMSFLEDLevels: UInt32 = 1

  private func queueMSFLEDLevel(_ signalHigh: Bool) {
    if pendingMSFLEDLevels & 0x8000_0000 == 0 {
      pendingMSFLEDLevels <<= 1
    }
    pendingMSFLEDLevels = (pendingMSFLEDLevels & ~1) | (signalHigh ? 1 : 0)
  }
#endif

private let panelSize = PixelSize(width: 64, height: 64)
private var hub75 = HUB75(panelSize: panelSize)

private func haltForever() {
  while true {
    tight_loop_contents()
  }
}

@main
struct Main {
  static func main() {

    stdio_init_all()

    let configuration = ClockConfiguration.current
    guard configuration.timeZone.makeCurrent() else {
      print("Failed to configure time zone")
      haltForever()
      return
    }

    if !hub75.start() {
      //SKLS_LOG_ERROR("Core 1 or HUB75 did not become ready\n");
      haltForever()
    }

    #if SK_RADIO_CLOCK_WIFI
      var wifi = WiFiService(ntpServer: configuration.ntpServer)
      if configuration.timeSource == .ntp {
        wifi.start()
      }
    #endif

    var selectedFace = ClockFaceKind.initial(for: configuration.timeSource)
    var renderer = Renderer(
      clockFace: ClockFaceInstance(kind: selectedFace, size: panelSize, configuration: configuration))

    #if SK_RADIO_CLOCK_RENDER_PROFILE
      var renderProfile = RenderProfile()
    #endif

    var clock = MSFClockModel()
    var acquisition = MSFClockAcquisition()
    var clockReporter = MSFClockReporter()

    let tPin: UInt32 = 26
    let p1Pin: UInt32 = 27
    let faceTogglePin: UInt32 = 28

    #if SK_RADIO_CLOCK_CYW43_LED
      // Only NTP starts WiFiService. MSF brings up CYW43 for the LED.
      let msfLEDReady = configuration.timeSource == .msf && cyw43_arch_init() == 0
      if configuration.timeSource == .msf && !msfLEDReady {
        print("MSF LED: CYW43 initialisation failed")
      }
    #else
      gpio_init(UInt32(PICO_DEFAULT_LED_PIN))
      gpio_set_dir(UInt32(PICO_DEFAULT_LED_PIN), true)
    #endif

    if configuration.timeSource == .msf {
      gpio_init(p1Pin)
      gpio_set_dir(p1Pin, true)
      gpio_put(p1Pin, false)
      gpio_init(tPin)
      gpio_set_dir(tPin, false)
    }

    gpio_init(faceTogglePin)
    gpio_set_dir(faceTogglePin, false)
    gpio_pull_up(faceTogglePin)

    var lastFaceRawPressed = !gpio_get(faceTogglePin)
    var stableFacePressed = lastFaceRawPressed
    var lastFaceChangeTime = time_us_64()

    let gpioIRQCallback: @convention(c) (UInt32, UInt32) -> Void = { gpio, events in

      let now: MSFTime = time_us_64()
      if events & UInt32(GPIO_IRQ_EDGE_RISE.rawValue) != 0 {
        msfScan.receiveSignalChange(.rising, at: now)
      } else if events & UInt32(GPIO_IRQ_EDGE_FALL.rawValue) != 0 {
        msfScan.receiveSignalChange(.falling, at: now)
      }

      // Both IRQ flags can latch during noise. Preserve both raw levels
      // without changing the decoder's existing edge-selection behavior.
      if events & UInt32(GPIO_IRQ_EDGE_FALL.rawValue) != 0 {
        msfScan.observeRawSignal(high: false, at: now)
      }
      let signalHigh = gpio_get(gpio)
      msfScan.observeRawSignal(high: signalHigh, at: now)

      #if SK_RADIO_CLOCK_CYW43_LED
        queueMSFLEDLevel(signalHigh)
      #else
        gpio_put(UInt32(PICO_DEFAULT_LED_PIN), signalHigh)
      #endif
    }

    if configuration.timeSource == .msf {
      let signalHigh = gpio_get(tPin)
      msfScan.observeRawSignal(high: signalHigh, at: time_us_64())
      #if SK_RADIO_CLOCK_CYW43_LED
        queueMSFLEDLevel(signalHigh)
      #endif
      gpio_set_irq_enabled_with_callback(
        tPin,
        UInt32(GPIO_IRQ_EDGE_RISE.rawValue | GPIO_IRQ_EDGE_FALL.rawValue),
        true,
        gpioIRQCallback
      )
    }

    while true {

      #if SK_RADIO_CLOCK_CYW43_LED
        if msfLEDReady {
          // Detach the batch with the MSF IRQ masked. CYW43 locks and bus I/O
          // run with interrupts enabled, before borrowing a framebuffer.
          let gpioIRQ = UInt32(IO_IRQ_BANK0.rawValue)
          let irqEnabled = irq_is_enabled(gpioIRQ)
          irq_set_enabled(gpioIRQ, false)
          let levels = pendingMSFLEDLevels
          pendingMSFLEDLevels = 1
          irq_set_enabled(gpioIRQ, irqEnabled)

          var mask = UInt32(1) << (31 - levels.leadingZeroBitCount)
          mask >>= 1  // Skip the marker.
          while mask != 0 {
            cyw43_arch_gpio_put(UInt32(CYW43_WL_GPIO_LED_PIN), levels & mask != 0)
            mask >>= 1
          }
        }
      #endif

      let now = time_us_64()
      let pressed = !gpio_get(faceTogglePin)

      if pressed != lastFaceRawPressed {
        lastFaceRawPressed = pressed
        lastFaceChangeTime = now
      }

      if pressed != stableFacePressed && now &- lastFaceChangeTime >= 30_000 {
        stableFacePressed = pressed

        if stableFacePressed {
          selectedFace = selectedFace.next(for: configuration.timeSource)
          renderer.setClockFace(
            ClockFaceInstance(kind: selectedFace, size: panelSize, configuration: configuration)
          )
        }
      }

      #if SK_RADIO_CLOCK_WIFI
        wifi.beginRendering()
      #endif

      var renderRequest = HUB75RenderRequest()
      if takeRenderRequest(&renderRequest) {
        #if SK_RADIO_CLOCK_RENDER_PROFILE
          renderProfile.recordReceived()
        #endif

        let snapshot: MSFDisplaySnapshot
        switch configuration.timeSource {
        case .msf:
          // Capture the MSF history with GPIO interrupts disabled.
          let gpioIRQ = UInt32(IO_IRQ_BANK0.rawValue)
          let irqEnabled = irq_is_enabled(gpioIRQ)
          irq_set_enabled(gpioIRQ, false)
          let rawSnapshot = msfScan.displaySnapshot(at: time_us_64())
          irq_set_enabled(gpioIRQ, irqEnabled)

          snapshot = MSFDisplaySnapshot(
            raw: rawSnapshot,
            clockSnapshot: clock.currentSnapshot(at: rawSnapshot.sampleTime)
              ?? acquisition.currentSnapshot(at: rawSnapshot.sampleTime)
              ?? .unknown
          )

        case .ntp:
          #if SK_RADIO_CLOCK_WIFI
            let clockSnapshot =
              wifi.currentUTC()
              .flatMap {
                ClockSnapshot(instant: $0, timeZone: configuration.timeZone)
              } ?? .unknown
          #else
            let clockSnapshot = ClockSnapshot.unknown
          #endif

          // Temporary adapter until rendering accepts ClockSnapshot directly.
          snapshot = MSFDisplaySnapshot(
            clockSnapshot: clockSnapshot,
            secondPhaseBin: nil,
            timestamp: time_us_64(),
            signalHigh: false,
            highBins: 0,
            lowBins: 0
          )
        }

        #if SK_RADIO_CLOCK_RENDER_PROFILE
          let startedAt = time_us_64()
        #endif

        let completed = renderer.render(&renderRequest, displaySnapshot: snapshot)

        #if SK_RADIO_CLOCK_RENDER_PROFILE
          let finishedAt = time_us_64()
          renderProfile.recordRender(
            startedAt: startedAt, finishedAt: finishedAt,
            deadline: renderRequest.deadline_us, completed: completed)
        #else
          _ = completed
        #endif
      }

      #if SK_RADIO_CLOCK_WIFI
        // SDK lock release may service pending packets. The framebuffer is no
        // longer used, and the next request has not yet been borrowed.
        wifi.endRendering()
        wifi.service(at: time_us_64())
      #endif

      var record = MSFFrameRecord(
        a_bits: 0, b_bits: 0, unknown_bits: 0,
        closing_marker_us: 0, data_count: 0, has_opening_marker: false)
      let hasFrame = msf_frame_take(&record)
      drainDiagnostics()
      if hasFrame {
        let completedFrame = MSFCompletedFrame(
          aBits: record.a_bits, bBits: record.b_bits,
          unknownBits: record.unknown_bits,
          dataCount: Int(record.data_count),
          hasOpeningMarker: record.has_opening_marker,
          closingMarkerTime: record.closing_marker_us)
        let result = completedFrame.decode()
        printFrame(completedFrame, result: result)
        let event: MSFClockEvent
        if clock.isAcquired || result.decodeStatus == .valid {
          event = clock.receive(completedFrame: completedFrame)
        } else {
          let acquisitionEvent = acquisition.receive(completedFrame: completedFrame)
          printAcquisition(acquisition, event: acquisitionEvent)
          if let supported = acquisition.supportedAcquisition() {
            event = clock.start(from: supported)
          } else {
            event = .unacquired
          }
        }

        clockReporter.report(event: event, clock: clock, at: completedFrame.closingMarkerTime)
      }

      clockReporter.reportPredictedMinute(clock: clock, at: time_us_64())

      #if SK_RADIO_CLOCK_RENDER_PROFILE
        if let statistics = renderProfile.takeReport(at: time_us_64()) {
          printRenderProfile(statistics)
        }
      #endif
    }
  }
}
