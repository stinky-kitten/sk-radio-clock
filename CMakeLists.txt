cmake_minimum_required(VERSION 3.29)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# == DO NOT EDIT THE FOLLOWING LINES for the Raspberry Pi Pico VS Code Extension to work ==
if(WIN32)
    set(USERHOME $ENV{USERPROFILE})
else()
    set(USERHOME $ENV{HOME})
endif()

set(sdkVersion 2.3.1)
set(toolchainVersion 15_2_Rel1)
set(picotoolVersion 2.3.1)

set(picoVscode ${USERHOME}/.pico-sdk/cmake/pico-vscode.cmake)
if(EXISTS ${picoVscode})
    include(${picoVscode})
endif()
# ====================================================================================

set(PICO_BOARD pico2_w CACHE STRING "Board type")

include("${CMAKE_CURRENT_LIST_DIR}/pico_sdk_import.cmake")

set(CMAKE_Swift_COMPILATION_MODE wholemodule)
set(CMAKE_Swift_COMPILER_WORKS YES)

project(sk-radio-clock)
pico_sdk_init()
enable_language(Swift)

# Download the pinned complete public binary, or use an optional local package.
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/AcquireSKLSHUB75.cmake")
find_package(SKLSHUB75 0.1.0 EXACT CONFIG REQUIRED
    PATHS "${SKLSHUB75_ROOT}/cmake" NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH)
# CMake's numeric package version omits the experimental suffix.
string(JSON _hub75_abi GET "${_hub75_pin}" abi_version)
if(NOT SKLSHUB75_PACKAGE_VERSION STREQUAL _hub75_version OR
   NOT SKLSHUB75_ABI_VERSION STREQUAL _hub75_abi)
    message(FATAL_ERROR "SKLSHUB75 package must match pinned ${_hub75_version}, ABI ${_hub75_abi}")
endif()
get_target_property(_hub75_library SKLSHUB75::hub75 IMPORTED_LOCATION)
message(STATUS "SKLSHUB75 ${SKLSHUB75_PACKAGE_VERSION}, ABI ${SKLSHUB75_ABI_VERSION}: ${_hub75_library}")

add_executable(sk-radio-clock
    # Source files:
    src/HUB75.swift
    src/config/ClockConfiguration.swift
    src/config/TimeSource.swift
    src/math/FloatingPoint.swift
    src/msf/acquisition/MSFAcquisitionEvent.swift
    src/msf/acquisition/MSFAcquisitionStatus.swift
    src/msf/acquisition/MSFClockAcquisition.swift
    src/msf/acquisition/MSFSupportedAcquisition.swift
    src/msf/clock/ClockSnapshot+MSF.swift
    src/msf/clock/MSFClockEvent.swift
    src/msf/clock/MSFClockModel.swift
    src/msf/clock/MSFMinuteGrid.swift
    src/msf/diagnostics/MSFClockReporter.swift
    src/msf/diagnostics/MSFDiagnostics.c
    src/msf/diagnostics/MSFDiagnostics.swift
    src/msf/display/MSFDisplaySnapshot.swift
    src/msf/epistemic/MSFEpistemicSecond.swift
    src/msf/epistemic/MSFEpistemicValue.swift
    src/msf/epistemic/MSFEvidenceFrame.swift
    src/msf/protocol/MSFChannel.swift
    src/msf/protocol/MSFCompletedFrame.swift
    src/msf/protocol/MSFExpectedFrame.swift
    src/msf/protocol/MSFField.swift
    src/msf/protocol/MSFFrameDecode.swift
    src/msf/protocol/MSFLogicalFrame.swift
    src/msf/protocol/MSFLogicalLayout.swift
    src/msf/protocol/MSFStructureAnalysis.swift
    src/msf/signal/MSFBits.swift
    src/msf/signal/MSFScan.swift
    src/msf/signal/MSFSecond.swift
    src/msf/signal/MSFTime.swift
    src/network/NTPUTCDiagnostic.swift
    src/network/NTPState.swift
    src/network/WiFiConnection.swift
    src/network/WiFiConfigurationValidation.swift
    src/render/AnalogueClockFace/AnalogueClockFace+Layout.swift
    src/render/AnalogueClockFace/AnalogueClockFace+Theme.swift
    src/render/AnalogueClockFace/AnalogueClockFace.swift
    src/render/AnalyticalClockFace/AnalyticalClockFace+Bits.swift
    src/render/AnalyticalClockFace/AnalyticalClockFace+ClockDate.swift
    src/render/AnalyticalClockFace/AnalyticalClockFace+ClockTime.swift
    src/render/AnalyticalClockFace/AnalyticalClockFace+Indicator.swift
    src/render/AnalyticalClockFace/AnalyticalClockFace+Layout.swift
    src/render/AnalyticalClockFace/AnalyticalClockFace+Theme.swift
    src/render/AnalyticalClockFace/AnalyticalClockFace+TimeZone.swift
    src/render/AnalyticalClockFace/AnalyticalClockFace+Trace.swift
    src/render/AnalyticalClockFace/AnalyticalClockFace.swift
    src/render/DigitalClockFace/DigitalClockFace.swift
    src/render/DigitalClockFace/DigitalClockFace+Layout.swift
    src/render/DigitalClockFace/DigitalClockFace+Theme.swift
    src/render/ClockFace.swift
    src/render/ClockFaceInstance.swift
    src/render/ClockFaceKind.swift
    src/render/ClockSnapshot+Formatting.swift
    src/render/ClockSnapshot+Render.swift
    src/render/ClockTheme.swift
    src/render/RenderProfile.swift
    src/render/Renderer.swift
    src/render/drawing/DrawingContext.swift
    src/render/drawing/DrawingContext+AntialiasedQuad.swift
    src/render/drawing/DrawingContext+Primitives.swift
    src/render/drawing/DrawingContext+SpanRasterTarget.swift
    src/render/drawing/DrawingContext+Text.swift
    src/render/drawing/PixelColor32.swift
    src/render/drawing/PixelCompositing.swift
    src/render/drawing/PixelFormat.swift
    src/render/drawing/SpanRasterTarget.swift
    src/render/fonts/Glyph.swift
    src/render/fonts/ClockFont.swift
    src/render/fonts/Font.swift
    src/render/fonts/MSFBitFont.swift
    src/render/fonts/PixelOperator8Font.swift
    src/render/geometry/DiskCoverage.swift
    src/render/geometry/DrawingGeometry.swift
    src/render/geometry/LineCoverage.swift
    src/render/geometry/PixelGeometry.swift
    src/render/geometry/TangentCircleCoverage.swift
    src/time/CalendarDateTimeComponents.swift
    src/time/CalendarDateTimeComponents+Formatting.swift
    src/time/CalendarDateTimeComponents+UTC.swift
    src/time/ClockSnapshot.swift
    src/time/ClockState.swift
    src/time/EpistemicState.swift
    src/time/TimeZone.swift
    src/time/TimeZoneConfiguration.swift
    src/time/UTCInstant.swift
)

# Swift conditional defines use presence/absence. Profiling is opt-in for
# every build configuration, including Release.
option(
    SK_RADIO_CLOCK_RENDER_PROFILE
    "Enable radio-clock render profiling"
    OFF
)

if(SK_RADIO_CLOCK_RENDER_PROFILE)
    target_compile_options(
        sk-radio-clock
        PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-DSK_RADIO_CLOCK_RENDER_PROFILE>"
    )
endif()

# Temporary synthetic circle workload. Normal firmware keeps its existing entry point.
set(SK_RADIO_CLOCK_CIRCLE_EXPERIMENT "OFF" CACHE STRING "Circle experiment: OFF, BASELINE, BINARY, AA, COMPARISON, FIVE_WAY, BENCHMARK or STATIONARY_AA")
set_property(CACHE SK_RADIO_CLOCK_CIRCLE_EXPERIMENT PROPERTY STRINGS OFF BASELINE BINARY AA COMPARISON FIVE_WAY BENCHMARK STATIONARY_AA)
if(SK_RADIO_CLOCK_CIRCLE_EXPERIMENT STREQUAL "OFF")
    target_sources(sk-radio-clock PRIVATE src/Main.swift)
else()
    if(NOT SK_RADIO_CLOCK_CIRCLE_EXPERIMENT MATCHES "^(BASELINE|BINARY|AA|COMPARISON|FIVE_WAY|BENCHMARK|STATIONARY_AA)$")
        message(FATAL_ERROR "Invalid SK_RADIO_CLOCK_CIRCLE_EXPERIMENT workload")
    endif()
    if(NOT SK_RADIO_CLOCK_RENDER_PROFILE)
        message(FATAL_ERROR "The circle experiment requires SK_RADIO_CLOCK_RENDER_PROFILE=ON")
    endif()
    target_sources(sk-radio-clock PRIVATE Experiments/Circles/CircleRenderExperiment.swift)
    if(SK_RADIO_CLOCK_CIRCLE_EXPERIMENT MATCHES "^(AA|COMPARISON|FIVE_WAY|BENCHMARK|STATIONARY_AA)$")
        target_sources(sk-radio-clock PRIVATE Experiments/Circles/RefinedChordCircle.swift)
    endif()
    if(SK_RADIO_CLOCK_CIRCLE_EXPERIMENT STREQUAL "COMPARISON")
        target_sources(sk-radio-clock PRIVATE
            Experiments/Circles/AnalyticalDiskCoverage.swift
            Experiments/Circles/CircleRenderComparison.swift)
    endif()
    if(SK_RADIO_CLOCK_CIRCLE_EXPERIMENT MATCHES "^(FIVE_WAY|BENCHMARK|STATIONARY_AA)$")
        target_sources(sk-radio-clock PRIVATE
            Experiments/Circles/AnalyticalDiskCoverage.swift
            Experiments/Circles/FiveWayCircleComparison.swift)
    endif()
    if(SK_RADIO_CLOCK_CIRCLE_EXPERIMENT MATCHES "^(BENCHMARK|STATIONARY_AA)$")
        target_sources(sk-radio-clock PRIVATE Experiments/Circles/CircleBenchmark.swift)
    endif()
    if(SK_RADIO_CLOCK_CIRCLE_EXPERIMENT STREQUAL "STATIONARY_AA")
        target_sources(sk-radio-clock PRIVATE Experiments/Circles/StationaryCircleComparison.swift)
    endif()
    target_compile_options(sk-radio-clock PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-DSK_RADIO_CLOCK_CIRCLE_${SK_RADIO_CLOCK_CIRCLE_EXPERIMENT}>")
endif()

set_target_properties(sk-radio-clock PROPERTIES LINKER_LANGUAGE CXX)

# Debug Swift Main.main has a 7424-byte frame, which overlaps Core 1 when
# Core 0 uses the default 4 KiB scratch Y bank. Nested Debug calls exceed
# 16 KiB, so reserve 32 KiB in main SRAM, excluding it from the heap, and
# retain Core 1's 2 KiB stack.
target_compile_definitions(sk-radio-clock PRIVATE PICO_STACK_SIZE=0x8000 PICO_CORE1_STACK_SIZE=0x800)
pico_set_linker_script_var(sk-radio-clock RAM_LENGTH 0x78000)
pico_set_linker_script_var(sk-radio-clock SCRATCH_Y_ORIGIN 0x20078000)
pico_set_linker_script_var(sk-radio-clock SCRATCH_Y_LENGTH 0x8000)

target_link_libraries(sk-radio-clock
    pico_stdlib 
    pico_multicore
    hardware_uart 
    hardware_gpio
    SKLSHUB75::hub75
)

# Build capability only: ClockConfiguration.current.timeSource in Swift selects what
# actually starts. Never read credentials or duplicate the selection in CMake.
set(_wifi_default OFF)
if(PICO_BOARD STREQUAL "pico2_w")
    set(_wifi_default ON)
endif()
if(PICO_CYW43_SUPPORTED)
    target_compile_options(sk-radio-clock PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-DSK_RADIO_CLOCK_CYW43_LED>")
endif()
option(SK_RADIO_CLOCK_WIFI "Build Pico 2 W Wi-Fi capability" ${_wifi_default})
if(SK_RADIO_CLOCK_CIRCLE_EXPERIMENT STREQUAL "BENCHMARK" AND SK_RADIO_CLOCK_WIFI)
    message(FATAL_ERROR "The circle benchmark requires SK_RADIO_CLOCK_WIFI=OFF")
endif()
if(SK_RADIO_CLOCK_WIFI AND NOT PICO_BOARD STREQUAL "pico2_w")
    message(FATAL_ERROR "SK_RADIO_CLOCK_WIFI requires PICO_BOARD=pico2_w; use OFF for Pico 2")
endif()
set(_local_config "${CMAKE_CURRENT_SOURCE_DIR}/Config/WiFiCredentials.swift")
# Notice a newly created local file on the next build, as well as edits/removal.
file(GLOB _local_config_present CONFIGURE_DEPENDS "${_local_config}")
if(SK_RADIO_CLOCK_WIFI AND NOT EXISTS "${_local_config}")
    message(FATAL_ERROR
        "Missing Config/WiFiCredentials.swift. Copy Config/WiFiCredentials.swift.example "
        "to Config/WiFiCredentials.swift, configure ClockConfiguration.current and local credentials. "
        "For NTP, set ntpServer in ClockConfiguration.current. "
        "Or configure with -DSK_RADIO_CLOCK_WIFI=OFF for MSF only.")
endif()
if(EXISTS "${_local_config}")
    target_sources(sk-radio-clock PRIVATE "${_local_config}")
else()
    target_sources(sk-radio-clock PRIVATE src/config/DefaultClockConfiguration.swift)
endif()
if(SK_RADIO_CLOCK_WIFI)
    target_sources(sk-radio-clock PRIVATE src/network/WiFiService.swift src/network/NTPService.swift)
    target_include_directories(sk-radio-clock PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src/network")
    target_link_libraries(sk-radio-clock pico_cyw43_arch_lwip_threadsafe_background pico_lwip_sntp pico_aon_timer)
    target_compile_definitions(sk-radio-clock PRIVATE SK_RADIO_CLOCK_WIFI=1
        PICO_CYW43_ARCH_DEBUG_ENABLED=0 PICO_CYW43_LOGGING_ENABLED=0
        PICO_STDIO_USB_STDOUT_TIMEOUT_US=0 PICO_STDIO_DEADLOCK_TIMEOUT_MS=0)
    target_compile_options(sk-radio-clock PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-DSK_RADIO_CLOCK_WIFI>")
else()
    if(PICO_CYW43_SUPPORTED)
        target_link_libraries(sk-radio-clock pico_cyw43_arch_none)
    endif()
    target_compile_options(sk-radio-clock PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-DSK_RADIO_CLOCK_NO_WIFI>")
endif()

# Clear the default COMPILE_OPTIONS which include C specific compiler flags that the Swift compiler will not accept
# Instead, set those options to only apply when compiling C code.
set_target_properties(pico_standard_link PROPERTIES INTERFACE_COMPILE_OPTIONS "")
target_compile_options(pico_standard_link INTERFACE "$<$<COMPILE_LANGUAGE:C>:SHELL: -ffunction-sections -fdata-sections>")

# Gather C compile definitions from all dependencies
set_property(GLOBAL PROPERTY visited_targets "")
set_property(GLOBAL PROPERTY compilerdefs_list "")

function(gather_compile_definitions_recursive target)
    # Get the current value of visited_targets
    get_property(visited_targets GLOBAL PROPERTY visited_targets)

    # make sure we don't visit the same target twice
    # and that we don't visit the special generator expressions
    if (${target} MATCHES "\\\$<" OR ${target} MATCHES "::@" OR ${target} IN_LIST visited_targets)
        return()
    endif()

    # Append the target to visited_targets
    list(APPEND visited_targets ${target})
    set_property(GLOBAL PROPERTY visited_targets "${visited_targets}")

    get_target_property(target_definitions ${target} INTERFACE_COMPILE_DEFINITIONS)
    if (target_definitions)
        # Append the target definitions to compilerdefs_list
        get_property(compilerdefs_list GLOBAL PROPERTY compilerdefs_list)
        list(APPEND compilerdefs_list ${target_definitions})
        set_property(GLOBAL PROPERTY compilerdefs_list "${compilerdefs_list}")
    endif()

    get_target_property(target_linked_libs ${target} INTERFACE_LINK_LIBRARIES)
    if (target_linked_libs)
        foreach(linked_target ${target_linked_libs})
            # Recursively gather compile definitions from dependencies
            gather_compile_definitions_recursive(${linked_target})
        endforeach()
    endif()
endfunction()

gather_compile_definitions_recursive(sk-radio-clock)
get_property(COMPILE_DEFINITIONS GLOBAL PROPERTY compilerdefs_list)

# Convert compiler definitions into a format that swiftc can understand
list(REMOVE_DUPLICATES COMPILE_DEFINITIONS)
list(PREPEND COMPILE_DEFINITIONS "") # adds a semicolon at the beginning
string(REPLACE "$<TARGET_PROPERTY:PICO_TARGET_BINARY_TYPE>" "$<TARGET_PROPERTY:sk-radio-clock,PICO_TARGET_BINARY_TYPE>" COMPILE_DEFINITIONS "${COMPILE_DEFINITIONS}")
string(REPLACE ";" " -Xcc -D" COMPILE_DEFINITIONS "${COMPILE_DEFINITIONS}")

# Compute -Xcc flags to set up the C and C++ header search paths for Swift (for bridging header).
# Keep paths quoted inside SHELL: groups for CMake's command-line parsing.
set(IMPLICIT_INCLUDES)
foreach(dir IN LISTS CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES)
    string(APPEND IMPLICIT_INCLUDES "-Xcc \"-I${dir}\" ")
endforeach()

set(SWIFT_TARGET armv6m-none-none-eabi)
set(SWIFT_FLOAT_ABI soft)
if(PICO_PLATFORM STREQUAL "rp2350-arm-s")
    set(SWIFT_TARGET armv7em-none-none-eabi)
    set(SWIFT_FLOAT_ABI softfp)
endif()

# Locate the active toolchain's PAL declarations without assuming a Swiftly path.
execute_process(
    COMMAND "${CMAKE_Swift_COMPILER}" -target "${SWIFT_TARGET}"
            -enable-experimental-feature Embedded -print-target-info
    RESULT_VARIABLE _swift_info_result
    OUTPUT_VARIABLE _swift_target_info
    ERROR_VARIABLE _swift_info_error
)
if(NOT _swift_info_result EQUAL 0)
    message(FATAL_ERROR "Cannot query Swift target info: ${_swift_info_error}")
endif()
string(JSON _swift_resource_dir ERROR_VARIABLE _swift_info_error
    GET "${_swift_target_info}" paths runtimeResourcePath)
if(_swift_info_error)
    message(FATAL_ERROR "Cannot locate Swift runtime resources: ${_swift_info_error}")
endif()
set(_swift_pal_include "${_swift_resource_dir}/../../include")
if(NOT EXISTS "${_swift_pal_include}/swift/EmbeddedPlatform.h")
    message(FATAL_ERROR "Missing Swift PAL declarations: ${_swift_pal_include}/swift/EmbeddedPlatform.h")
endif()
# The 2026-10-27 bare-metal PAL archives contain only empty BSD indices;
# converting them to GNU archives cannot supply code. Use the Pico SDK-backed
# functions needed by this firmware, checked against the toolchain's header.
# The September snapshot can also compile these; unused functions are discarded.
target_sources(sk-radio-clock PRIVATE src/platform/SwiftPlatform.c)
set_source_files_properties(src/platform/SwiftPlatform.c PROPERTIES
    INCLUDE_DIRECTORIES "${_swift_pal_include}"
    # EmbeddedPlatform.h uses C23 fixed-underlying-type enums for 64-bit flags.
    COMPILE_OPTIONS "-std=gnu23")

target_compile_options(sk-radio-clock PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:
        -target ${SWIFT_TARGET}
        -Xcc -mfloat-abi=${SWIFT_FLOAT_ABI}
        -enable-experimental-feature Embedded
        -parse-as-library
        -module-name swift_radio_clock

        -Xcc -fshort-enums
        -Xfrontend -function-sections
        -import-bridging-header \"${CMAKE_CURRENT_LIST_DIR}/src/BridgingHeader.h\"
        ${COMPILE_DEFINITIONS}
        ${IMPLICIT_INCLUDES}
    >")

if(TARGET pico_float_pico_vfp)
    set_target_properties(pico_float_pico_vfp PROPERTIES INTERFACE_COMPILE_OPTIONS "")
    target_compile_options(pico_float_pico_vfp INTERFACE "$<$<COMPILE_LANGUAGE:C>:SHELL: -fno-math-errno>")
endif()

pico_enable_stdio_usb(sk-radio-clock 1)
pico_enable_stdio_uart(sk-radio-clock 0)

pico_add_extra_outputs(sk-radio-clock)
pico_set_printf_implementation(sk-radio-clock pico)
