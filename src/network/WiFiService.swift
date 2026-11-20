//
//  WiFiService.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-28.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// Core 0 foreground application. SDK/background callbacks never call Swift or render.
struct WiFiService {
  private static let displayName: StaticString = "SK Radio Clock"
  private static let hostname: StaticString = "sk-radio-clock"
  private var connection = WiFiConnection()
  private var ntp = NTPService()
  private let ntpServer: StaticString?
  private var enabled = false
  private var startupFailure: StaticString?
  private var startupError: Int32 = 0
  private var nextPollUs: UInt64 = 0
  private var nextReportUs: UInt64 = 0
  private var previousAddress: UInt32 = 0
  private var previouslyAssociated = false
  #if SK_RADIO_CLOCK_RENDER_PROFILE
    private var renderLockStartedUs: UInt64 = 0
    private var acquireMaxUs: UInt64 = 0
    private var holdMaxUs: UInt64 = 0
    private var releaseMaxUs: UInt64 = 0
  #endif

  init(ntpServer: StaticString?) {
    self.ntpServer = ntpServer
  }

  // Startup only, after HUB75 reserves PIO0 SM0/SM1 and before foreground rendering.
  // Firmware loading/STA setup can take time; Core 1 continues initial scanout.
  mutating func start() {
    guard WiFiConfigurationValidation.hasNTPServer(ntpServer) else {
      let error: StaticString = "set ntpServer to a hostname or IPv4 address in Config/WiFiCredentials.swift"
      startupFailure = error
      log(error)
      return
    }
    let error = WiFiCredentials.ssid.withUTF8Buffer { ssid in
      WiFiCredentials.password.withUTF8Buffer { password in
        WiFiConfigurationValidation.error(ssid: ssid, password: password)
      }
    }
    if let error {
      startupFailure = error
      log(error)
      return
    }
    let result = cyw43_arch_init_with_country(radio_clock_country_uk)
    guard result == 0 else {
      startupFailure = "initialisation failed; reboot to retry"
      startupError = result
      log(startupFailure!, detail: result)
      return
    }
    cyw43_arch_lwip_begin()
    enableStation()
    cyw43_arch_lwip_end()
    enabled = true
    log("initialised UK; station enabled; NTP acquisition available")
    log(Self.displayName)
    log(Self.hostname)
  }

  // Core 0 is the only application caller of this async context. Acquire before
  // borrowing a framebuffer: any wait/preemption here consumes no buffer lease.
  // The recursive lock defers the SDK worker, not host-wake/alarm/USB interrupts.
  mutating func beginRendering() {
    guard enabled else { return }
    #if SK_RADIO_CLOCK_RENDER_PROFILE
      let started = time_us_64()
    #endif
    cyw43_arch_lwip_begin()
    #if SK_RADIO_CLOCK_RENDER_PROFILE
      renderLockStartedUs = time_us_64()
      acquireMaxUs = max(acquireMaxUs, renderLockStartedUs &- started)
    #endif
  }

  mutating func endRendering() {
    guard enabled else { return }
    #if SK_RADIO_CLOCK_RENDER_PROFILE
      let started = time_us_64()
      holdMaxUs = max(holdMaxUs, started &- renderLockStartedUs)
    #endif
    // Outermost unlock may run pending SDK work synchronously. The framebuffer
    // must no longer be used; this work can delay the next request's service.
    cyw43_arch_lwip_end()
    #if SK_RADIO_CLOCK_RENDER_PROFILE
      releaseMaxUs = max(releaseMaxUs, time_us_64() &- started)
    #endif
  }

  // Called only after releasing the borrowed render request. No join wait loop.
  mutating func service(at now: UInt64) {
    guard enabled || startupFailure != nil, now >= nextPollUs else { return }
    guard enabled, let ntpServer else {
      nextPollUs = now + 10_000_000
      if let startupFailure { log(startupFailure, detail: startupError) }
      return
    }
    nextPollUs = now + 250_000
    let snapshot = readSnapshot()
    let previousPhase = connection.phase
    if snapshot.associated && !previouslyAssociated { log("AP associated; awaiting DHCP") }
    previouslyAssociated = snapshot.associated
    let action = connection.step(at: now, status: snapshot.status, hasAddress: snapshot.ipv4 != 0)
    if action == .connect {
      log("starting asynchronous WPA2 attempt; prior failures (capped)", detail: Int32(connection.failureCount))
      let result = cyw43_arch_wifi_connect_async(
        UnsafeRawPointer(WiFiCredentials.ssid.utf8Start).assumingMemoryBound(to: CChar.self),
        UnsafeRawPointer(WiFiCredentials.password.utf8Start).assumingMemoryBound(to: CChar.self),
        UInt32(CYW43_AUTH_WPA2_AES_PSK))
      if result != 0 {
        log("join start failed", detail: result)
        _ = connection.startFailed(at: time_us_64())
        disconnect()
      }
    } else if action == .disconnect {
      disconnect()
    }
    if connection.phase == .backoff && (previousPhase != .backoff || action == .connect) {
      switch connection.failure {
      case .authentication: log("authentication failed (credentials/security)")
      case .unavailable: log("network unavailable")
      case .timeout: log("association/DHCP timed out")
      case .lost: log("connectivity lost")
      case .link: log("link failed", detail: snapshot.status)
      case .start, .none: break
      }
      let reportedAt = time_us_64()
      let remainingUs = connection.nextAttemptUs > reportedAt ? connection.nextAttemptUs - reportedAt : 0
      let remaining = (remainingUs + 999_999) / 1_000_000
      log("retry in seconds", detail: Int32(remaining))
    }
    if connection.phase == .online && (previousPhase != .online || previousAddress != snapshot.ipv4) {
      log("DHCP address acquired; connectivity ready", ipv4: snapshot.ipv4)
    }
    ntp.service(online: connection.phase == .online, server: ntpServer)
    previousAddress = snapshot.ipv4
    // Repeat status so a terminal opened after boot can verify initialisation.
    if now >= nextReportUs {
      nextReportUs = now + 10_000_000
      log(
        "status; TCP/IP status (-3 auth,-2 no AP,-1 fail,0 down,1 join,2 DHCP,3 up)",
        detail: snapshot.status, ipv4: snapshot.ipv4)
      #if SK_RADIO_CLOCK_RENDER_PROFILE
        log("render lock acquire max us", detail: Int32(clamping: acquireMaxUs))
        log("render lock hold max us", detail: Int32(clamping: holdMaxUs))
        log("render lock release/service max us", detail: Int32(clamping: releaseMaxUs))
      #endif
    }
  }

  func currentUTC() -> UTCInstant? {
    ntp.currentUTC()
  }

  // Caller holds the lwIP lock. SDK creates a link-down netif and starts DHCP
  // in INIT; no packet is sent before link-up. Set this before releasing the
  // lock (and before joining), including after every STA recreation.
  private func enableStation() {
    cyw43_arch_enable_sta_mode()
    cyw43_state.netif.0.hostname = UnsafeRawPointer(Self.hostname.utf8Start).assumingMemoryBound(to: CChar.self)
  }

  private func disconnect() {
    // SDK STA disable removes the netif/DHCP lease. Guard that lwIP access too.
    cyw43_arch_lwip_begin()
    cyw43_arch_disable_sta_mode()
    enableStation()
    cyw43_arch_lwip_end()
  }

  private func readSnapshot() -> (status: Int32, associated: Bool, ipv4: UInt32) {
    cyw43_arch_lwip_begin()
    defer { cyw43_arch_lwip_end() }
    let associated = cyw43_wifi_link_status(&cyw43_state, Int32(CYW43_ITF_STA)) == CYW43_LINK_JOIN
    let status = cyw43_tcpip_link_status(&cyw43_state, Int32(CYW43_ITF_STA))
    // SDK cyw43_t.netif[2] imports as a tuple; STA is entry 0 (CYW43_ITF_STA).
    // With LWIP_IPV6=0, ip_addr_t is ip4_addr_t. No cast/accessor macro needed.
    let address = withUnsafePointer(to: &cyw43_state.netif.0) { interface -> UInt32 in
      guard status == CYW43_LINK_UP, dhcp_supplied_address(interface) != 0 else { return 0 }
      return UInt32(bigEndian: interface.pointee.ip_addr.addr)
    }
    return (status, associated, address)
  }

  private func log(_ message: StaticString, detail: Int32 = 0, ipv4: UInt32 = 0) {
    print("WiFi: ", terminator: "")
    print(message, terminator: "")
    print(" detail=", terminator: "")
    print(detail, terminator: "")
    print(" ipv4=", terminator: "")
    print(ipv4 >> 24, terminator: ".")
    print((ipv4 >> 16) & 255, terminator: ".")
    print((ipv4 >> 8) & 255, terminator: ".")
    print(ipv4 & 255)
  }
}
