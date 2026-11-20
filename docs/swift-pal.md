# Embedded Swift Platform Support on RP2350

## Why a platform layer is needed

Embedded Swift calls platform-provided runtime functions when generated code uses facilities such as heap allocation, standard output or fatal-error reporting. This firmware supplies those functions through a small C Platform Abstraction Layer (PAL) backed by the Pico SDK. Swift describes the runtime contract in its [platform-porting documentation](https://docs.swift.org/latest/documentation/embeddedswift/portingtonewplatforms/) and shows how to link SDK code in its [Pico integration guide](https://docs.swift.org/latest/documentation/embeddedswift/integratewithpico/).

The installed macOS `swift-DEVELOPMENT-SNAPSHOT-2026-10-27-a` toolchain's two `armv7em-none-none-eabi` PAL archives, `libswiftEmbeddedPlatformPOSIX.a` and `libswiftEmbeddedPlatformSingleThreaded.a`, are 88 bytes each. Each contains only an empty BSD `__.SYMDEF` symbol index. The original inspection found no implementation members with `llvm-ar t` and no definitions with `llvm-nm --print-armap`. GNU-format repacking produced two 8-byte archives containing only the archive signature. Link order and whole-archive options cannot supply absent object code. This finding applies to those target archives in that installation.

The [upstream POSIX implementation](https://github.com/swiftlang/swift/blob/b5fe9234c4eb9b4ab1c840913f5689203ce43ad4/stdlib/public/EmbeddedPlatform/EmbeddedPlatformPOSIX.swift) relies on `posix_memalign`, which the qualified GNU/newlib target could not link. The [upstream single-threaded implementation](https://github.com/swiftlang/swift/blob/b5fe9234c4eb9b4ab1c840913f5689203ce43ad4/stdlib/public/EmbeddedPlatform/EmbeddedPlatformSingleThreaded.swift) uses no-op output locks. The Pico-specific PAL provides aligned allocation and serialises Swift output across cores using the SDK services already linked by the application.

## Runtime interfaces

[`src/platform/SwiftPlatform.c`](../src/platform/SwiftPlatform.c) implements seven entry points. These are the C definitions, checked against the installed [`swift/EmbeddedPlatform.h`](https://github.com/swiftlang/swift/blob/b5fe9234c4eb9b4ab1c840913f5689203ce43ad4/stdlib/public/EmbeddedPlatform/swift/EmbeddedPlatform.h).

```c
void *_swift_allocate(size_t alignment, size_t size, swift_alloc_flags_t flags);
void _swift_deallocate(void *pointer, size_t alignment, size_t size, swift_dealloc_flags_t flags);
void _swift_typedDeallocate(void *pointer, size_t size, size_t alignment,
                            swift_dealloc_flags_t flags, __swift_typeid_t typeId);

void _swift_lockStandardOutput(void);
size_t _swift_writeToStandardOutput(const unsigned char *chars, size_t count);
void _swift_unlockStandardOutput(void);

void _swift_reportErrorAt(const unsigned char *message, size_t messageCount,
                          const unsigned char *fileName, size_t fileNameCount,
                          size_t line, __swift_options_t flags);
```

Allocation and ordinary deallocation take alignment before size. Typed deallocation takes size before alignment and forwards both in the ordinary deallocator's order, ignoring the type ID. Allocation and deallocation flags, error-reporting options and type IDs are 64-bit, including when the build uses short enums. `SWIFT_ALLOC_ZERO_MEMORY` requires zeroing the requested bytes before returning them. The output and error interfaces take counted UTF-8 buffers. Swift holds the recursive stdout lock across a complete print, including its terminator, and the write hook returns the number of input bytes accepted by the SDK. The error hook is intentionally silent.

## Pico SDK implementation

### Memory allocation

The PAL uses the SDK's wrapped `malloc` and `free`, retaining the SDK's multicore heap locking and configured allocation-failure checks. It rejects alignments below `sizeof(void *)` or outside the powers of two. It reserves one payload byte for a zero-sized request and rejects overflow before adding the payload and alignment overhead. A null result from `malloc` is returned as failure when the SDK lets the call return. Any configured SDK out-of-memory panic still applies.

The allocation reserves `sizeof(void *) + alignment - 1` extra bytes. The PAL rounds up to the requested alignment after reserving space for a pointer, then stores the original allocation immediately before the returned address. The paired deallocator recovers that pointer, so it can free an allocation with unknown size or alignment and treats a null pointer as a no-op. The adjusted pointer must go through PAL deallocation. Passing it directly to ordinary `free` would bypass the stored pointer.

### Standard output

An SDK auto-initialised recursive mutex serialises complete Swift prints between cores. Recursion allows formatting a value to invoke Swift printing again. `_swift_writeToStandardOutput` passes explicitly counted chunks to `stdio_put_string`, each limited to `INT_MAX`. It enables the SDK's normal CR/LF handling, adds no newline of its own and stops if a write reports no progress. The SDK separately serialises individual stdio writes. Direct C output can interleave with Swift prints, and a returned byte count does not establish delivery over USB.

### Error reporting

`_swift_reportErrorAt` returns without reading its buffers, allocating, acquiring locks or invoking SDK drivers. The runtime may call it before stdio is ready, in an interrupt or after a failure while SDK locks are held. The recursive Swift lock cannot establish safe progress through those conditions. The installed PAL contract permits an empty reporter, after which Swift issues its terminating trap with failure and source debug information. This implementation emits no fatal-error text.

## ABI and toolchain compatibility

The qualified Pico 2 and Pico 2 W configuration uses Pico SDK 2.3.1, Arm GNU 15.2.Rel1 (GCC 15.2.1) and the October snapshot (Swift revision `b5fe9234c4eb9b4ab1c840913f5689203ce43ad4`, LLVM `7211ac1d2aee144`). The firmware targets RP2350 Arm secure mode. Swift uses `armv7em-none-none-eabi`, whose Thumb-2 instruction subset can run on the Cortex-M33. Recorded `arm-none-eabi-readelf -h -A` inspection identified little-endian ELF32 Arm EABI5 objects, short enums and 8-byte stack alignment on both the Swift and C sides. The Swift object reported Armv7E-M and the C object Armv8-M Mainline.

The current Swift configuration passes `-Xcc -mfloat-abi=softfp` and `-Xcc -fshort-enums`. With this toolchain, `softfp` enables native VFP arithmetic while retaining base AAPCS argument passing. The original inspection used Swift `soft`, which uses software floating-point arithmetic with the same calling convention. The `hard` ABI changes floating-point argument passing to VFP registers. See the [build requirements](../README.md#build-requirements) for compiler selection.

[CMake](../CMakeLists.txt) queries the selected Swift compiler with `-print-target-info`, derives the toolchain include path from `runtimeResourcePath` and requires the installed `swift/EmbeddedPlatform.h`. It applies that include path and GNU C23 mode to the C PAL source. The header's fixed-underlying-type enums preserve the flags ABI under short-enum compilation. Swift imports firmware SDK declarations separately through [the bridging header](../src/BridgingHeader.h). [SwiftPM](../Package.swift) excludes the firmware platform directory from host builds.

The earlier `swift-DEVELOPMENT-SNAPSHOT-2026-09-21-a` header compiled with this PAL, although it did not yet declare the stdout lock functions. Its legacy Embedded Swift runtime still left an unresolved `posix_memalign` reference in a recorded firmware link. That path expects pointers compatible with ordinary `free`. Header compatibility therefore establishes only the source-level contract.

## Verification and limitations

Recorded Debug and Release builds linked on both Pico 2 and Pico 2 W with the completed PAL. `arm-none-eabi-nm -u` reported no undefined symbols in the four final ELFs. Debug retained all seven entry points, including typed deallocation and source-located error reporting. Release retained only the three stdout entry points in those builds. A same-configuration comparison before and after adding the two Debug-support functions showed no change in Release text, data, BSS, BIN length or UF2 length on either board. BIN contents differed because of link layout. Symbol retention and size results are specific to those builds.

Recorded host PAL checks passed against both the October and September headers under AddressSanitizer and UndefinedBehaviorSanitizer with short enums. The [test harness](../HostSupport/SwiftPlatformTests/test.py) checks allocation alignment, zero-fill, zero sizes, overflow and failure, typed and untyped deallocation, counted and partial writes, recursive locking and the silent reporter. A second pass instruments typed deallocation to check exact argument forwarding. Run it with a host Clang that supports fixed-underlying-type C enums and the sanitizers.

```sh
python3 HostSupport/SwiftPlatformTests/test.py /path/to/swift-toolchain/usr/include
```

The host doubles exercise the PAL contract. Hardware mutex behaviour, USB delivery and fatal-error handling require on-device evidence. The developer reported running the Pico 2 W firmware on hardware. Pico 2 and Debug hardware operation were outside that validation, and no fatal error was deliberately triggered on hardware.
