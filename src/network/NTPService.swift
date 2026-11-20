//
//  NTPService.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-28.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

// SNTP callbacks run under the SDK context lock. They only publish fixed data.
private var ntpReceipt: NTPReceipt?
private var ntpRequestActive = false

@_cdecl("radio_clock_sntp_sample")
func ntpSample(_ seconds: UInt32, _ fraction: UInt32) {
  guard ntpRequestActive else { return }
  NTPReceipt.publish(seconds: seconds, fraction: fraction, receivedAt: time_us_64(), into: &ntpReceipt)
}

@_cdecl("radio_clock_sntp_nonce")
func ntpNonce(_ seconds: UnsafeMutablePointer<UInt32>?, _ microseconds: UnsafeMutablePointer<UInt32>?) {
  let now = time_us_64()
  seconds?.pointee = UInt32(truncatingIfNeeded: now / 1_000_000)
  microseconds?.pointee = UInt32(now % 1_000_000)
}

// Bundled SNTP omits leap/stratum/version checks. The supported IPv4 input hook
// rejects those invalid UDP/123 responses before SNTP; protocol parsing, origin
// validation and retry handling still belong to the SDK. Hook owns dropped pbufs.
@_cdecl("radio_clock_sntp_filter")
func ntpFilter(_ packet: UnsafeMutablePointer<pbuf>?) -> Int32 {
  guard let packet, pbuf_get_at(packet, 9) == 17 else { return 0 }
  let headerLength = UInt16(pbuf_get_at(packet, 0) & 15) * 4
  guard headerLength >= 20, packet.pointee.tot_len >= headerLength + 56,
    pbuf_get_at(packet, headerLength) == 0, pbuf_get_at(packet, headerLength + 1) == 123
  else { return 0 }
  let valid = NTPState.validServerHeader(
    pbuf_get_at(packet, headerLength + 8),
    stratum: pbuf_get_at(packet, headerLength + 9))
  if !valid {
    _ = pbuf_free(packet)
    return 1
  }
  return 0
}

struct NTPService {
  private var state = NTPState()
  private var timerValid = false
  private var nextReportUs: UInt64 = 0

  // Core 0 foreground only; called outside framebuffer use. Callback never
  // accesses POWMAN, so no foreground/IRQ AON read-modify race is possible.
  mutating func service(online: Bool, server: StaticString) {
    cyw43_arch_lwip_begin()
    let receipt = ntpReceipt
    ntpReceipt = nil
    cyw43_arch_lwip_end()
    let now = time_us_64()
    if let receipt {
      if state.accepts(instant: receipt.instant, receivedAt: receipt.receivedAt),
        now >= receipt.receivedAt, now - receipt.receivedAt <= NTPState.requestTimeoutUs
      {
        // One-time delivery-latency adjustment, not an advancing UTC accumulator.
        let nanoseconds = UInt64(receipt.instant.nanoseconds) + (now - receipt.receivedAt) * 1_000
        var timestamp = timespec(
          tv_sec: time_t(receipt.instant.unixSeconds + Int64(nanoseconds / 1_000_000_000)),
          tv_nsec: Int(nanoseconds % 1_000_000_000)
        )
        let started = time_us_64()
        let accepted = timerValid ? aon_timer_set_time(&timestamp) : aon_timer_start(&timestamp)
        let elapsed = time_us_64() - started
        if accepted {
          timerValid = true
          state.success(at: receipt.receivedAt)
          print("NTP: synchronised; AON write us=", terminator: "")
          print(elapsed)
          report(at: now, online: online)
        } else {
          state.failure(at: now)
          print("NTP: AON update failed")
        }
        stop()
      } else {
        print("NTP: rejected stale/out-of-range sample")
      }
    }
    if let start = state.startedAt, !online || now - start >= NTPState.requestTimeoutUs {
      stop()
      state.failure(at: now)
      print("NTP: attempt failed (network loss, DNS/server timeout or invalid response); retry in 60s")
    }
    if online, state.startedAt == nil, now >= state.nextAttemptUs {
      state.start(at: now)
      cyw43_arch_lwip_begin()
      ntpReceipt = nil
      ntpRequestActive = true
      sntp_setservername(0, UnsafeRawPointer(server.utf8Start).assumingMemoryBound(to: CChar.self))
      sntp_init()
      cyw43_arch_lwip_end()
      print("NTP: synchronisation started")
    }
    if now >= nextReportUs {
      nextReportUs = now + 60_000_000
      report(at: now, online: online)
    }
  }

  private func stop() {
    cyw43_arch_lwip_begin()
    ntpRequestActive = false
    ntpReceipt = nil
    sntp_stop()
    cyw43_arch_lwip_end()
  }

  private func report(at now: UInt64, online: Bool) {
    guard timerValid, let last = state.lastSuccessUs else {
      print("NTP: never synchronised")
      return
    }
    var timestamp = timespec()
    let started = time_us_64()
    guard aon_timer_get_time(&timestamp) else {
      print("NTP: AON read failed")
      return
    }
    let elapsed = time_us_64() - started
    print("NTP: UTC=", terminator: "")
    if let utc = NTPUTCDiagnostic.make(seconds: timestamp.tv_sec, nanoseconds: Int64(timestamp.tv_nsec)) {
      for index in 0..<24 { _ = putchar(Int32(utc.bytes[index])) }
    } else {
      print("unavailable", terminator: "")
    }
    print(" unix=", terminator: "")
    print(timestamp.tv_sec, terminator: " nsec=")
    print(timestamp.tv_nsec, terminator: " age_s=")
    print((now - last) / 1_000_000, terminator: " online=")
    print(online, terminator: " last_attempt_failed=")
    print(state.failed, terminator: " AON read us=")
    print(elapsed)
  }

  func currentUTC() -> UTCInstant? {
    guard timerValid else { return nil }

    var timestamp = timespec()
    guard aon_timer_get_time(&timestamp) else { return nil }

    return UTCInstant(timestamp: timestamp)
  }
}

extension UTCInstant {
  init(timestamp: timespec) {
    self.unixSeconds = Int64(timestamp.tv_sec)
    self.nanoseconds = UInt32(timestamp.tv_nsec)
  }
}
