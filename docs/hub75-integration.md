# HUB75 Driver Integration

## Binary dependency

The clock links the RP2350 driver from the public [`skls-hub75-dist` v0.1.0-experimental.3 release](https://github.com/stinky-kitten/skls-hub75-dist/releases/tag/v0.1.0-experimental.3). The package supplies the static library, compiled PIO programs, public headers, Swift module map and API notes. These are sufficient to build the clock without access to the private driver source. The driver has its own binary library licence and third-party notices, listed in the [clock's licence index](../LICENSES/README.md). The driver and its Swift API remain experimental.

## Build integration

CMake uses [the shared JSON pin](../Dependencies/SKLSHUB75.json) to download the `rp2350-arm-s` ZIP. It verifies the ZIP's SHA-256, extracts it under the build directory's `_deps/` and verifies the manifest and every pinned payload file, including files reused from the extracted cache. It checks the full package version and ABI 1 after loading the CMake package, then links `libskls_hub75.a` through `SKLSHUB75::hub75`. The firmware uses Embedded Swift's direct `import SKLSHUB75`.

SwiftPM resolves the exact version in the same pin. [`Package.resolved`](../Package.resolved) records revision `826ad354235e8c93ddac96722a09287c167b25a7`. Host builds and tests use the declaration-only product, including its headers, module map and API notes. The Arm archive is only linked by the firmware build. Keep downloaded ZIPs, extracted packages and SwiftPM checkouts in build directories or a local cache outside Git.

For offline CMake builds, `-DSKLSHUB75_ARCHIVE=/path/to/the/pinned.zip` uses the normal checksum and extraction path. `-DSKLSHUB75_ROOT=/path/to/package` selects an unpacked override. CMake checks that its required files, version and ABI match expectations and bypasses release checksums for this development path. SwiftPM accepts `SKLSHUB75_ROOT` as an environment variable to import declarations from an unpacked package without resolving the remote dependency.

## Hardware and ABI contract

The same ABI 1 archive targets Pico 2 and Pico 2 W in RP2350 Arm secure mode (`rp2350-arm-s`), with Pico SDK 2.3.1 and a 150 MHz system clock. The ABI identifier is `rp2350-arm-s-aapcs-softfp-short-enums-v1-profile00`. The provider qualifies Arm GNU 15.2.Rel1. The clock's Swift importer uses `-mfloat-abi=softfp` and `-fshort-enums` to match base AAPCS argument passing and enum layout. Hard-float calling conventions are incompatible. See the driver's [ABI contract](https://github.com/stinky-kitten/skls-hub75-dist/blob/v0.1.0-experimental.3/docs/ABI.md) for the complete requirements and qualified configuration.

The clock uses the driver's default panel pinout. The driver rejects GP23–25 and GP29 for HUB75 signals on both boards. The optional MSF receiver uses GP26 for signal input and GP27 for enable, outside that panel pinout. The driver reserves Core 1 and PIO0 SM0/SM1, needs 21 PIO0 instruction slots and dynamically claims one DMA channel. Other users of PIO0 and DMA must leave those resources available. The driver retains its PIO program-space and DMA claims across stop and reconfiguration. The clock reserves 32 KiB of stack for Core 0 and 2 KiB for Core 1.

Core 0 initialises the driver and launches the Core 1 scanout worker. Each render request lends Core 0 a driver-owned framebuffer until an absolute deadline in the Pico monotonic microsecond timebase. Core 1 proceeds independently of foreground rendering. Core 0 must stop writing before the deadline and must never free the buffer or retain it through stop or reconfiguration. The clock's cooperative checks can leave a frame partially drawn and cannot guarantee timely completion during a drawing operation or interrupt. See [framebuffer ownership](analogue-clock.md#framebuffer-ownership).

## Verification and limitations

From the repository root, use the resolved SwiftPM checkout and a copy of the release ZIP to verify the pin, archive, manifest and payload checksums, and compare the SwiftPM declarations with the archive:

```sh
python3 tools/check_hub75_release.py \
  --distribution .build/checkouts/skls-hub75-dist \
  --archive /path/to/skls-hub75-0.1.0-experimental.3-rp2350-arm-s.zip
```

The pinned ZIP's manifest and CMake metadata carry an old pre-publication status label. The consumer verifies the published ZIP and its contents by checksum independently of that label.

Host builds and tests exercise the imported declarations and application logic. A firmware build additionally checks target compilation and linkage against the Arm library. Electrical compatibility, PIO/DMA coexistence, physical scanout, render-deadline compliance and long-running reliability require on-device verification.
