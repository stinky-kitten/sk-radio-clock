# MSF diagnostics transport host boundary

The SwiftPM `MSFDiagnosticsTransport` Clang target compiles the original
`src/msf/diagnostics/MSFDiagnostics.c` and exports its original header. Only
this target searches `include` for the host `hardware/sync.h`.

The replacement header provides the two interrupt functions required by the
source, with compiler-ordering fences for deterministic sequential tests. It
does not reproduce interrupt masking, preemption, timing or multicore safety.
Firmware CMake continues to select the genuine Pico SDK header.

One serialized Swift Testing suite owns the C transport's process-global
state. Each case empties it through the production APIs before and after use;
the private indices are not reset. The existing scanner tests retain their
separate Swift output capture and do not call this transport.

Tests cover observable capacity and physical ring reuse. UInt32 index rollover
and drop-counter saturation are checked in production source, rather than
forced through billions of operations or private-state injection. Record
sizes are not asserted as API guarantees. Hardware interrupt safety still
requires on-device verification.
