# Wi-Fi connectivity and local configuration

The default Pico 2 W build uses Wi-Fi for [NTP acquisition](ntp.md). After synchronisation, the RP2350 always-on (AON) timer supplies UTC and the clock converts it to the configured local time zone for display. MSF is a separate, receiver-based mode. The clock does not switch time sources automatically.

## Configuration and builds

For a first build, follow the [Pico 2 W setup](../README.md#getting-started). Copy [`Config/WiFiCredentials.swift.example`](../Config/WiFiCredentials.swift.example) to `Config/WiFiCredentials.swift`, keep `timeSource: .ntp`, and supply your Wi-Fi credentials and an explicit NTP server. The example leaves `ntpServer` unset. Use `ntpServer: "ntp.example.net"` as the syntax, substituting a hostname or IPv4 address you are authorised to use. Wi-Fi requires a 2.4 GHz WPA2-Personal network.

`ClockConfiguration.current` supplies the time source, time zone, theme and NTP server. Edit the arguments in the local Swift extension. `.standard` is the only supported theme. The clock faces receive the complete configuration, with panel size passed separately. The build does not rewrite an existing local selection.

NTP startup rejects an unset or empty server value and accepts only printable ASCII without spaces for a supplied value. This check does not verify that the server resolves or responds. The SSID must contain 1–32 UTF-8 bytes without NUL and the passphrase must contain 8–63 printable ASCII bytes. The template SSID and password are rejected. Startup reports these errors before initialising Wi-Fi, without printing the supplied values. The credentials and server are `StaticString` values, which provide static storage for SDK C-string arguments. MSF does not use those settings.

| Time source | What starts | Initial face and GP28 button cycle |
| --- | --- | --- |
| `.ntp` | UK CYW43 configuration and station mode, then asynchronous WPA2 association, DHCP and SNTP. Time stays unknown until the first successful synchronisation. | Starts on analogue. GP28 switches between analogue and digital. |
| `.msf` | Receiver GPIO, interrupts and MSF acquisition. Pico 2 W initialises CYW43 for the onboard LED without enabling station mode or joining an AP. | Starts on analytical. GP28 cycles through analytical, analogue and digital. |

`SK_RADIO_CLOCK_WIFI` controls the compiled networking capability. The local Swift configuration selects what actually starts. On a fresh CMake configuration, `PICO_BOARD` defaults to `pico2_w`. Wi-Fi capability defaults to ON on Pico 2 W and OFF on Pico 2.

| Board and capability | Required configuration and behaviour |
| --- | --- |
| Pico 2 W, ON | The local Swift file is required for either time source. A missing file is a CMake configuration error that explains how to copy the example. |
| Pico 2 W, OFF | Wi-Fi and NTP are omitted. CYW43 remains linked through `pico_cyw43_arch_none` for the MSF LED. Without a local file, [`DefaultClockConfiguration.swift`](../src/config/DefaultClockConfiguration.swift) selects `.msf`. A local file must also select `.msf`. |
| Pico 2, OFF | Same MSF configuration selection, with the onboard LED driven directly through GP25. |
| Pico 2, ON | CMake rejects the combination. |

With capability OFF, `TimeSource.ntp` is unavailable at compile time. Use separate build directories for different boards and set the capability explicitly when reusing a cached build. The next build detects additions or removals of the local file and compiles edits to it.

## Swift and SDK integration

[`WiFiService`](../src/network/WiFiService.swift) handles validation, CYW43 startup, asynchronous join requests, SDK locking, STA resets, link and DHCP reads, diagnostics and dispatch to the NTP service. It calls imported SDK functions directly from Swift. [`WiFiConnection`](../src/network/WiFiConnection.swift) is the foreground connection state machine. It consumes a timestamp, SDK link status and address availability, and produces a connection or disconnection action without making SDK calls.

[`BridgingHeader.h`](../src/BridgingHeader.h) makes the CYW43 architecture declarations available to both wireless-board variants and exposes lwIP/DHCP/SNTP and AON declarations when lwIP is enabled. The function-like expansion behind `CYW43_COUNTRY_UK` does not import into Swift, so the header exposes the SDK's value as `static const uint32_t radio_clock_country_uk = CYW43_COUNTRY_UK;`. `WiFiService` passes that value to `cyw43_arch_init_with_country` and uses `cyw43_arch_wifi_connect_async` with `CYW43_AUTH_WPA2_AES_PSK`.

The `netif_ip4_addr`, `ip4_addr_get_u32` and `lwip_ntohl` accessor macros do not import. With `LWIP_IPV6=0`, the STA netif is tuple entry zero and Swift reads `cyw43_state.netif.0.ip_addr.addr` under the SDK lock. `UInt32(bigEndian:)` converts the address word for dotted-decimal diagnostics. `dhcp_supplied_address` and the inline `cyw43_arch_lwip_begin/end` locks import directly. Diagnostics use Swift printing because C variadic `printf` is unavailable through the importer.

To reproduce the Arm compiler probes, use a configured Pico 2 W Ninja build with `SK_RADIO_CLOCK_WIFI=ON`:

```sh
python3 tools/check_wifi_interop.py build
```

The script reuses that build's compiler and SDK flags to compile isolated probes for the supported declarations and expected importer failures. It does not read or compile private credential source. Results and logs go to `wifi-interop-checks/` under the supplied build directory.

## DHCP hostname

The diagnostic display name is `SK Radio Clock`. The DHCP hostname is `sk-radio-clock`, independent of the private configuration. `LWIP_NETIF_HOSTNAME=1` exposes the station netif's `hostname` field. The assigned pointer is backed by a `StaticString` with static lifetime.

SDK 2.3.1 creates the STA netif and starts DHCP during station enable. While the link is down, DHCP stays in INIT without sending a request. Under the same lwIP lock, `enableStation()` sets the hostname before the application starts association. Station reset runs the same helper and reapplies the hostname. The bundled lwIP uses that field for DHCP option 12 in Discover and Request packets, including renewals. Router lease labels can be cached or assigned locally, so inspect the packet to verify the advertised value. The firmware implements DHCP naming only. It provides no mDNS advertisement, `.local` resolution, DNS server or discovery service.

## Scheduling, locking and recovery

HUB75 starts first, reserving PIO0 SM0/SM1, 21 PIO instruction slots and a dynamically claimed DMA channel. Core 1 continues initial scanout while Core 0 brings up CYW43 before foreground rendering. The wireless driver uses SDK resource claims. See [HUB75 hardware](../README.md#hub75-hardware) for the display configuration.

In MSF mode, Pico 2 mirrors the sampled receiver GPIO level on its GP25 onboard LED directly from the GPIO interrupt. On Pico 2 W, the interrupt queues levels for the foreground to write to the CYW43-controlled LED. The initial receiver level is also queued, and the bounded queue preserves the latest level if it fills. Foreground LED I/O runs with interrupts enabled before the framebuffer is borrowed. If CYW43 initialisation fails, the firmware reports the LED error and continues MSF reception. This LED path works in the firmware with Wi-Fi capability ON or OFF.

The NTP build uses `pico_cyw43_arch_lwip_threadsafe_background` with `NO_SYS=1`, IPv4, UDP, DHCP, DNS and SNTP. TCP, sockets and IPv6 are disabled. Core 0 owns the async context and all application networking calls. The Swift SNTP callbacks exposed to lwIP handle fixed-size data under the SDK context lock. AON updates remain in the foreground. See [NTP acquisition](ntp.md) for the callback and clock details.

When `WiFiService` is enabled, Core 0 acquires the recursive SDK context lock before asking for a HUB75 render request. It releases the lock after the final framebuffer access, or immediately after checking for a request when none is available. With SDK 2.3.1, the low-priority background handler defers worker processing while the foreground holds the lock. Host-wake, alarm bookkeeping, USB and other interrupts can still preempt the foreground. Lock acquisition is blocking, but it occurs before borrowing the buffer and the application has no Core 1 networking callers.

The outermost unlock can run pending network work synchronously. This is outside framebuffer use, but can delay servicing the next request and leave less render-start slack. Holding the lock also delays network servicing during rendering. The framebuffer remains driver-owned and can rotate at the absolute deadline without an acknowledgement. The [renderer checks deadlines cooperatively](analogue-clock.md#framebuffer-ownership). A row whose check has passed can finish writing after ownership changes, and cancellation can leave a partial frame. The network lock provides no hard real-time guarantee.

`WiFiService` polls on a 250 ms schedule from the foreground, after releasing the render lock. Association alone is insufficient for connectivity. The SDK must report link-up and DHCP must supply a nonzero IPv4 address before the connection is online and NTP can start. Each connection attempt has a 30-second association and DHCP budget, checked on the foreground poll. Authentication, unavailable network and other link failures can end an attempt sooner.

Failures schedule retries after 5, 10, 20 and then 30 seconds indefinitely. The failure counter saturates at tier 4 and resets when the connection reaches online. Loss of an established link or address therefore starts again at the five-second tier. One locked STA disable/enable resets the netif and DHCP state after each failure. Backoff polls do not repeatedly reset the station. Initialisation failure requires reboot. Join-start failures, authentication failures, an unavailable network, link loss, association/DHCP timeout, retry delay and a new lease each have diagnostics. Startup configuration and initialisation errors are repeated on a ten-second schedule. The normal status report pairs the address with the SDK TCP/IP link status: −3 authentication failure, −2 no AP, −1 link failure, 0 down, 1 joining, 2 awaiting DHCP and 3 up.

Wi-Fi-capable builds disable CYW43 debug logging and set the SDK USB stdout and stdio mutex wait timeouts to zero. A stalled USB reader can result in dropped or partial diagnostics. Capability-OFF builds retain the SDK timeout defaults.

With `SK_RADIO_CLOCK_RENDER_PROFILE=ON`, the ten-second Wi-Fi status reports include cumulative maxima for lock acquisition, the protected interval and unlock/service time in microseconds. These elapsed times include preemption. The [render profiler](../README.md#optional-rendering-profiling) reports completion and rejection counts, render duration, start slack, `late_start` and `late_done`. Start slack is the time from entry to the renderer to the request deadline, after snapshot preparation. `late_done` counts successful renders that finish at or after the deadline. Neither a zero count nor observed maxima establish a worst-case bound on framebuffer access.

## Private configuration and source distribution

**Locally compiled firmware can contain Wi-Fi credentials.** The release publishes source, including `Config/WiFiCredentials.swift.example`. Each builder supplies a private `Config/WiFiCredentials.swift` and builds their own firmware. Git ignores that path. Review the files and artefacts selected for publication, including any files that have already been tracked or copied elsewhere.

CMake selects the local Swift file as a source without reading its credential values into the cache, compiler definitions or generated headers. The formatting check skips the local file, but compiler diagnostics can quote its source. Keep the real configuration, local build logs and locally compiled images private.

## Hardware verification and diagnostics

### Recorded hardware observations

The developer verified WPA2 association, DHCP lease acquisition, loss detection, capped retries and automatic AP-outage recovery without restarting on Pico 2 W. The [NTP hardware record](ntp.md#validation-and-hardware-procedure) also documents synchronisation, AON time advancing while offline, reconnection and UTC serial diagnostics. Host tests and importer probes exercise code paths and SDK declarations. They cannot establish RF behaviour or render timing on a panel.

### Reader checks

1. **Initial connection and time.** Flash a Pico 2 W Release build with `.ntp`, valid local credentials and a reachable NTP server. Open the USB CDC serial device and reset. Boot output can precede enumeration, so allow for the repeated status messages. Look for WPA2 association, a nonzero DHCP address, SNTP synchronisation and correct local time on both faces. A terminal's 115200 setting, if required by its UI, is conventional for USB CDC.
2. **DHCP hostname.** Check the new lease on the router. Capture the clock's DHCP Discover and Request packets and verify option 12 contains `sk-radio-clock`, including after reconnection. A router label alone does not establish the advertised value.
3. **Failure and recovery.** Try a wrong but syntactically valid passphrase, an unavailable AP and association without a responding DHCP server. Check the distinct failure or timeout reports and the 5/10/20/30-second retry schedule. Restore valid settings, obtain a lease, then turn off the AP long enough for the clock to reach capped backoff. Restore the AP and look for a fresh lease on a subsequent attempt. The scheduled delay after a failure is at most 30 seconds. Polling, loss detection and the subsequent association/DHCP attempt add their own latency. After connectivity succeeds, repeat the outage to check that the first retry returns to five seconds.
4. **Rendering under network load.** Cycle both faces with GP28 during joins, online operation and reconnects. Compare profiling ON/OFF with the same panel and HUB75 settings. With profiling enabled, record lock maxima, starts, completions, rejections, minimum start slack and late completions. Watch for stalls, flicker or corruption during busy LAN traffic. Treat any `late_done` count as a failure of this check. If the results are marginal, correlate worker timing and scanout with SWD tracing or instrumentation on a verified spare pin.
5. **Optional MSF check.** When a live receiver is available, select `.msf` and verify signal indication, acquisition and all three faces without a Wi-Fi join. On Pico 2 W, repeat with networking compiled out to exercise the LED-only CYW43 configuration. On Pico 2, check the GP25 LED path.

### Outstanding verification

DHCP option 12 still needs on-wire verification. Worst-case network and render interference, deadline slack and physical timing remain uncharacterised. Live MSF receiver verification is currently unavailable, so the MSF LED paths and live reception are described from code rather than reported as retested on either board.
