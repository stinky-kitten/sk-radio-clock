# NTP acquisition and RP2350 UTC timekeeping

In `.ntp` mode, the Pico 2 W starts Wi-Fi and waits for DHCP before starting lwIP's asynchronous SNTP client. The client uses the hostname or IPv4 address explicitly supplied as `ntpServer` in the local `ClockConfiguration.current` initializer. There is no built-in server or automatic fallback to MSF. See the [Pico 2 W setup](../README.md#getting-started) and the [networking guide](networking.md) for configuration and connection policy.

On RP2350, Pico SDK 2.3.1's linear `aon_timer_start` API starts the XOSC-derived 1 kHz POWMAN timer with the first accepted UTC sample. Later synchronisations apply corrections with `aon_timer_set_time`. The firmware reads UTC with `aon_timer_get_time`. This follows the hardware timekeeping approach in Raspberry Pi's [ntp_system_time example](https://github.com/raspberrypi/pico-examples/blob/master/pico_w/wifi/ntp_system_time/ntp_system_time.c).

lwIP delivers the raw NTP fraction to Swift, which truncates it to whole nanoseconds. The RP2350 SDK truncates the resulting `timespec` to whole milliseconds when writing the timer. The timer advances UTC in hardware while Wi-Fi is unavailable. This build provides no battery-backed persistence across power loss. Offline accuracy depends on the oscillator and the time elapsed since the last correction. Request timers, sync age and render deadlines use the separate monotonic `time_us_64()` clock, so UTC corrections do not move their deadlines.

The NTP render path reads the AON timer and constructs a `ClockSnapshot` using the configured time zone. The analogue and digital faces receive local calendar fields through the snapshot. Until the timer has been set successfully, or if the timer read or local conversion fails, the snapshot reports unknown time. Serial diagnostics use UTC regardless of the display time zone.

## Response validation and synchronisation policy

- **lwIP SNTP.** With `SNTP_CHECK_RESPONSE=2`, polling checks the expected server address and source port, a 48-byte payload and server response mode. Stratum zero is handled as Kiss-of-Death without publishing a sample. Other responses must echo the most recently sent request timestamp in the originate field.
- **Application IPv4 input hook.** For UDP packets with source port 123 and enough bytes for the UDP and SNTP headers and payload, the hook rejects leap indicator 3 (unsynchronised), versions other than 3 and 4, and stratum above 15. lwIP invokes the hook before IPv4 reassembly. Some fragmented datagrams can reach SNTP after reassembly without passing those additional header checks on the complete datagram. The lwIP SNTP checks and Swift sample validation still apply.
- **Swift receipt and foreground checks.** The callback only admits samples while an application request is active. It discards a raw transmit timestamp with both words zero before era unfolding and leaves any pending receipt intact. A zero seconds word with a nonzero fraction can represent a legitimate sample at the February 2036 rollover. It still has to pass the same date and timing checks. Conversion follows lwIP's era convention around the 2036 rollover, and the foreground accepts only UTC dates in 2020–2099, nanoseconds below one billion and receipt timestamps inside the active 30-second window. The sample must also be no more than 30 seconds old when consumed.

For DNS query IDs and source-port selection, lwIP uses the Pico SDK's `LWIP_RAND()`, backed by `get_rand_32()`. The application leaves that SDK definition in place. SNTP origin matching separately uses a request timestamp derived from monotonic time, which is available before the first UTC fix. Round-trip compensation is disabled because that request timestamp does not represent UTC. SNTP remains unauthenticated and provides neither NTS nor cryptographic anti-spoofing protection. It is unsuitable as a security-grade time source.

The SNTP callback writes the raw timestamp's converted value and monotonic reception time into a fixed-size, single-receipt mailbox. Core 0 foreground takes and clears the mailbox under the SDK lwIP context lock. It releases the lock before applying the sample, after framebuffer use has ended. Before writing the AON timer, it adds the monotonic receipt-to-foreground delay once. This adjustment only accounts for local delivery latency. Timer updates and validity metadata belong to the foreground, and the callbacks perform no timer updates or printing. Swift calls the imported linear AON and SNTP APIs directly, with `lwipopts.h` binding lwIP's callback macros to C-callable Swift functions.

A successful AON update stops SNTP and makes the next attempt due one hour after the accepted sample's monotonic receipt time. An attempt without a usable sample expires after 30 seconds, and loss of connectivity can end it earlier. After a failed attempt or AON write, the next attempt is due 60 seconds after failure and starts only once the connection is online. An outage or failed refresh preserves an already established clock. If an outage occurs between attempts, the existing refresh deadline remains in force. The failed-attempt log lists possible causes because the foreground cannot distinguish network loss, DNS or server timeouts, and rejected replies from that outcome alone.

When stopping an attempt, the application clears the mailbox and closes sample admission before calling `sntp_stop()`. The bundled lwIP stop routine removes the SNTP UDP endpoint and cancels the request and server-retry timers. A DNS callback already registered with the resolver can still run after stop and may schedule retry work. This remains a lifecycle limitation identified by code inspection. No crash or incorrect clock update from it has been demonstrated.

## UTC diagnostics

Foreground logs report acquisition, stale or out-of-range samples, attempt failures and AON read or write failures. The status report is due once a minute and is also emitted after a successful synchronisation. Before the first successful update it reports that the clock has never synchronised. After synchronisation a successful AON read yields a line in this form:

```text
NTP: UTC=<YYYY-MM-DDTHH:MM:SS.sssZ> unix=<seconds> nsec=<nanoseconds> age_s=<age> online=true last_attempt_failed=false AON read us=<measured>
```

`NTPUTCDiagnostic` uses `gmtime_r` to produce a 24-byte ISO 8601 UTC field independently of the display time zone. It truncates nanoseconds to three millisecond digits and appends `Z`. It accepts Unix seconds from the epoch through `9999-12-31T23:59:59Z` and nanoseconds in `0...999_999_999`. The bridging header checks that the firmware's `time_t` is 64-bit, and the formatter requires an exact conversion to that type. Out-of-range input, invalid calendar fields or a failed UTC conversion yield `UTC=unavailable`. The report still includes the raw Unix seconds and nanoseconds from the AON read.

UTC conversion and serial output run in the foreground outside the lwIP lock and framebuffer ownership. The reported AON read and write durations use the monotonic microsecond timer around the SDK calls and exclude conversion and serial formatting.

## Implementation measurements

These are historical observations from Pico 2 W Release builds with profiling disabled. The sizes are comparison baselines for those builds.

| Change | Text | BSS |
| --- | ---: | ---: |
| Initial DNS/SNTP/AON integration | 426,700 → 435,948 bytes (+9,248) | 105,992 → 107,200 bytes (+1,208) |
| ISO 8601 UTC diagnostics | 435,948 → 437,632 bytes (+1,684) | 107,200 → 107,200 bytes |

The UTC diagnostic change left the data section at zero bytes. The initial size change covers the full integration. It gives no breakdown of the AON component or of peak stack and heap usage. Recorded diagnostics showed an AON write duration of approximately **30 µs** and a read duration of approximately **11 µs**. These are configuration-specific observations without worst-case timing guarantees.

## Hardware verification and diagnostics

**Recorded on Pico 2 W.** The developer verified SNTP acquisition, continued AON UTC advancement through Wi-Fi outages, reconnection and ISO 8601 serial reports. The operation timings above were observed on that hardware.

**Host regression coverage.** Existing tests exercise rejection of the all-zero timestamp without replacing a pending receipt, valid rollover fractions, era and date boundaries, request windows, failure and recovery, scheduling overflow and the header-quality predicate. UTC diagnostic tests cover known dates, leap day, the 2038 boundary, fractions and failure cases. Snapshot tests exercise local conversion on both sides of the 2026 UK clock changes. These tests cover the application logic without simulating the POWMAN timer or the SDK's packet receive path.

### Validation and hardware procedure

The following checks can be used for regression testing. The failure-injection cases and worst-case timing checks are separate from the recorded hardware observations.

1. Start a Pico 2 W NTP build with a reachable configured server. Check the DHCP and synchronisation logs, compare reported UTC and raw Unix seconds with a trusted reference, and check both faces against the configured local time.
2. Observe periodic reports through an hourly refresh. Remove Wi-Fi between attempts and check that UTC continues to advance with `online=false`. Restore connectivity and verify the next eligible refresh. Compare AON time with a reference over a longer offline interval to measure drift.
3. In a controlled network, test an unavailable server or an unresolvable hostname. Check the bounded failure report, the 60-second online retry and recovery. With a controlled test server, verify that malformed or incorrect-origin responses do not establish time.
4. Switch faces during acquisition and refresh. Compare render duration, slack, late completions and SDK lock timing with profiling disabled and enabled. Worst-case render interference, oscillator drift and the effects of a DNS callback completing after stop remain uncharacterised on hardware.
