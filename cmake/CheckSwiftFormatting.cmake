# Use the same source scope on every platform without scanning build products,
# downloaded dependencies, or obsolete test directories outside the active targets.
get_filename_component(SK_SOURCE_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
if(NOT DEFINED SK_SWIFT_EXECUTABLE)
    find_program(SK_SWIFT_EXECUTABLE NAMES swift REQUIRED)
endif()

file(GLOB_RECURSE SK_SWIFT_SOURCES LIST_DIRECTORIES false
    "${SK_SOURCE_ROOT}/src/*.swift"
    "${SK_SOURCE_ROOT}/Experiments/Circles/*.swift"
    "${SK_SOURCE_ROOT}/tools/*.swift"
    "${SK_SOURCE_ROOT}/Tests/RadioClockTests/*.swift"
    "${SK_SOURCE_ROOT}/Tests/MSFTransportTests/*.swift"
)
list(APPEND SK_SWIFT_SOURCES "${SK_SOURCE_ROOT}/Package.swift"
    "${SK_SOURCE_ROOT}/Config/WiFiCredentials.swift.example")
# Local secrets are deliberately excluded from tools that echo source diagnostics.
# These checked-in font tables are generated; check their generators instead.
list(REMOVE_ITEM SK_SWIFT_SOURCES
    "${SK_SOURCE_ROOT}/src/render/fonts/ClockFont.swift"
    "${SK_SOURCE_ROOT}/src/render/fonts/PixelOperator8Font.swift"
)
list(SORT SK_SWIFT_SOURCES)
list(LENGTH SK_SWIFT_SOURCES SK_SWIFT_SOURCE_COUNT)
message(STATUS "Checking formatting of ${SK_SWIFT_SOURCE_COUNT} maintained Swift files")

# lint never writes source files. --strict makes warnings fail the check too.
execute_process(
    COMMAND "${SK_SWIFT_EXECUTABLE}" format lint
        --strict --no-color-diagnostics
        --configuration "${SK_SOURCE_ROOT}/.swift-format"
        ${SK_SWIFT_SOURCES}
    WORKING_DIRECTORY "${SK_SOURCE_ROOT}"
    RESULT_VARIABLE SK_SWIFT_LINT_RESULT
)
if(NOT SK_SWIFT_LINT_RESULT STREQUAL "0")
    message(FATAL_ERROR "Swift formatting check failed (${SK_SWIFT_LINT_RESULT})")
endif()
