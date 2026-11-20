# The VS Code build tasks use Ninja and need one explicit initial configure.
if(NOT EXISTS "${SK_BUILD_DIR}/CMakeCache.txt" OR NOT EXISTS "${SK_BUILD_DIR}/build.ninja")
    message(FATAL_ERROR
        "Build directory is not configured. Run the VS Code task '${SK_CONFIGURE_TASK}' first.")
endif()
