//
//  WiFiTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-28.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

@Test func ntpRequiresAnExplicitServer() {
  #expect(!WiFiConfigurationValidation.hasNTPServer(nil))
  #expect(!WiFiConfigurationValidation.hasNTPServer(""))
  #expect(!WiFiConfigurationValidation.hasNTPServer(" "))
  #expect(!WiFiConfigurationValidation.hasNTPServer("ntp.example.net\0other"))
  #expect(WiFiConfigurationValidation.hasNTPServer("ntp.example.net"))
  #expect(WiFiConfigurationValidation.hasNTPServer("192.0.2.1"))
}

@Test("Local WPA2 validation checks byte lengths, placeholders and C string safety")
func wifiConfigurationValidation() {
  #expect(wifiConfigurationError(ssid: "Home", password: "password") == nil)
  #expect(wifiConfigurationError(ssid: String(repeating: "é", count: 16), password: "12345678") == nil)
  #expect(wifiConfigurationError(ssid: String(repeating: "é", count: 17), password: "12345678") != nil)
  for ssid in ["", "a\0b", "YOUR_WIFI_SSID", String(repeating: "x", count: 33)] {
    #expect(wifiConfigurationError(ssid: ssid, password: "12345678") != nil)
  }
  for password in [
    "short", "1234567\0", "1234567\n", "1234567é", "YOUR_WIFI_PASSWORD", String(repeating: "x", count: 64),
  ] {
    #expect(wifiConfigurationError(ssid: "Home", password: password) != nil)
  }
  #expect(wifiConfigurationError(ssid: "Home", password: String(repeating: "x", count: 63)) == nil)
}

@Test("Association alone does not establish DHCP connectivity; loss recovers")
func wifiAssociationDHCPAndRecovery() {
  var wifi = WiFiConnection()
  #expect(wifi.step(at: 0, status: 0, hasAddress: false) == .connect)
  #expect(wifi.failureCount == 0)
  #expect(wifi.step(at: 250_000, status: 1, hasAddress: false) == .none)
  #expect(wifi.phase == .connecting)
  #expect(wifi.step(at: 500_000, status: 2, hasAddress: false) == .none)
  #expect(wifi.phase == .associated)
  #expect(wifi.step(at: 750_000, status: 3, hasAddress: false) == .none)
  #expect(wifi.phase != .online)
  #expect(wifi.step(at: 1_000_000, status: 3, hasAddress: true) == .none)
  #expect(wifi.phase == .online)
  #expect(wifi.failureCount == 0)
  #expect(wifi.step(at: 2_000_000, status: 0, hasAddress: true) == .disconnect)
  #expect(wifi.failure == .lost)
  #expect(wifi.step(at: 6_999_999, status: 0, hasAddress: false) == .none)
  #expect(wifi.step(at: 7_000_000, status: 0, hasAddress: false) == .connect)
  #expect(wifi.step(at: 8_000_000, status: 3, hasAddress: true) == .none)
  #expect(wifi.phase == .online)
}

@Test("Retries follow 5/10/20/30 seconds indefinitely and reset after DHCP")
func wifiCappedRetries() {
  var wifi = WiFiConnection()
  var now: UInt64 = 0
  for failure in 1...100 {
    #expect(wifi.step(at: now, status: 0, hasAddress: false) == .connect)
    #expect(wifi.step(at: now + 1, status: -3, hasAddress: false) == .disconnect)
    #expect(wifi.failure == .authentication)
    #expect(wifi.failureCount == min(failure, 4))
    let delay: UInt64 = failure == 1 ? 5_000_000 : failure == 2 ? 10_000_000 : failure == 3 ? 20_000_000 : 30_000_000
    #expect(wifi.nextAttemptUs == now + 1 + delay)
    #expect(wifi.step(at: wifi.nextAttemptUs - 1, status: 0, hasAddress: false) == .none)
    now = wifi.nextAttemptUs
  }
  #expect(wifi.step(at: now, status: 0, hasAddress: false) == .connect)
  _ = wifi.step(at: now + 1, status: 2, hasAddress: false)
  #expect(wifi.failureCount == 4)
  _ = wifi.step(at: now + 2, status: 3, hasAddress: true)
  #expect(wifi.failureCount == 0)
  #expect(wifi.step(at: now + 3, status: 0, hasAddress: false) == .disconnect)
  #expect(wifi.failure == .lost)
  #expect(wifi.nextAttemptUs == now + 3 + 5_000_000)
  #expect(wifi.failureCount == 1)
}

@Test("Unavailable AP, DHCP timeout and immediate SDK failures are distinguished")
func wifiFailures() {
  var wifi = WiFiConnection()
  _ = wifi.step(at: 0, status: 0, hasAddress: false)
  #expect(wifi.step(at: 100, status: -2, hasAddress: false) == .disconnect)
  #expect(wifi.failure == .unavailable)
  let retry = wifi.nextAttemptUs
  _ = wifi.step(at: retry, status: 0, hasAddress: false)
  _ = wifi.step(at: retry + 1, status: 2, hasAddress: false)
  #expect(wifi.step(at: retry + WiFiConnection.attemptTimeoutUs - 1, status: 2, hasAddress: false) == .none)
  #expect(wifi.step(at: retry + WiFiConnection.attemptTimeoutUs, status: 2, hasAddress: false) == .disconnect)
  #expect(wifi.failure == .timeout)
  let next = wifi.nextAttemptUs
  _ = wifi.step(at: next, status: 0, hasAddress: false)
  #expect(wifi.startFailed(at: next) == .disconnect)
  #expect(wifi.failure == .start)
}

private func wifiConfigurationError(ssid: String, password: String) -> StaticString? {
  WiFiConfigurationValidation.error(ssid: ssid.utf8, password: password.utf8)
}
