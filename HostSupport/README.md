# Host test boundaries

Host renderer tests import the authentic `SKLSHUB75` public Clang module and API
notes from the exact-version `skls-hub75-dist` SwiftPM product selected by
`Dependencies/SKLSHUB75.json` and recorded by `Package.resolved`. Normal `swift test`
needs no private driver path. The declaration-only C anchor exposes header search paths
through standard SwiftPM; it defines no hardware implementation functions.

An optional `SKLSHUB75_ROOT` environment variable uses an unpacked binary package's
public include directory instead, without resolving the remote dependency. There
is no copied `HUB75RenderRequest` declaration or independently maintained wrapper header.
Renderer and its tests use the same `HUB75RenderRequest` imported from the
release API notes; no application-specific HUB75 C bridge is involved.
The module map has no archive autolink; macOS tests do not link the Arm library or
need the Pico SDK. The host pointer layout follows macOS; the firmware ABI is
specified and validated by the distribution. Firmware uses its imported CMake target.

`MSFDiagnosticsTransport/include` remains the host interrupt boundary for the
separate production C diagnostics transport and MSFTransportTests.

The public v0.1.0-experimental.3 tag resolves to
`826ad354235e8c93ddac96722a09287c167b25a7`. Anonymous public resolution and clean
CLI host tests have been verified; no local mirror is required. VS Code uses the same manifest and resolver; its live
Testing workflow was verified on earlier releases and was not repeated for `.3`.
