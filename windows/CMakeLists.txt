# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(typemate LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "typemate")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Speech runtime provisioning ===
# The bundled models and binaries are gitignored (they exceed git hosting
# limits), so fetch anything missing automatically. This makes a fresh clone
# build and run without manual steps; the script is a fast no-op when the
# files are already present.
#
# Reading the generated config inside a function gives its PARENT_SCOPE
# writes (FLUTTER_VERSION etc.) a parent, which they lack at the top level
# and would otherwise warn about on every configure.
function(typemate_resolve_dart_executable out_variable)
  include("${FLUTTER_MANAGED_DIR}/ephemeral/generated_config.cmake" OPTIONAL)
  if(DEFINED FLUTTER_ROOT)
    set(${out_variable} "${FLUTTER_ROOT}/bin/dart.bat" PARENT_SCOPE)
  else()
    set(${out_variable} "dart" PARENT_SCOPE)
  endif()
endfunction()
typemate_resolve_dart_executable(DART_EXECUTABLE)
execute_process(
  COMMAND "${DART_EXECUTABLE}" tool/fetch_whisper_runtime.dart
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.."
  RESULT_VARIABLE WHISPER_FETCH_RESULT
)
if(NOT WHISPER_FETCH_RESULT EQUAL 0)
  message(FATAL_ERROR
    "Failed to provision the bundled whisper runtime (model + CLI). "
    "Check your network connection or run manually: "
    "dart run tool/fetch_whisper_runtime.dart")
endif()
# Re-check on every build (not just configure) so a deleted model heals
# itself without a flutter clean.
add_custom_target(whisper_runtime ALL
  COMMAND "${DART_EXECUTABLE}" tool/fetch_whisper_runtime.dart
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.."
  COMMENT "Checking bundled whisper runtime (model + CLI)")
add_dependencies(${BINARY_NAME} whisper_runtime)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Bundle the whisper runtime (model + CLI) next to the executable so
# dictation works without any user configuration. Provision the source
# folders with tool/fetch_whisper_runtime.dart. Fully re-copy the models
# directory on each build so retired models do not linger in the bundle.
set(WHISPER_MODEL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../models")
if(EXISTS "${WHISPER_MODEL_DIR}")
  install(CODE "
    file(REMOVE_RECURSE \"${CMAKE_INSTALL_PREFIX}/models\")
    " COMPONENT Runtime)
  install(DIRECTORY "${WHISPER_MODEL_DIR}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime)
endif()
set(WHISPER_CLI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../bin")
if(EXISTS "${WHISPER_CLI_DIR}")
  install(DIRECTORY "${WHISPER_CLI_DIR}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Ship the MSVC runtime next to the executable. Fresh Windows installs
# often lack the VC++ redistributable and the app then exits on launch
# without a message. Prefer the toolchain's redist folder; fall back to
# the build machine's System32 copies (same redistributable files).
set(TYPEMATE_CRT_DLLS "")
foreach(crt_dll msvcp140.dll vcruntime140.dll vcruntime140_1.dll)
  # Sysnative reaches the real 64-bit System32 when CMake itself runs as a
  # 32-bit process (plain System32 would silently redirect to the 32-bit
  # SysWOW64 copies and ship the wrong architecture).
  if(DEFINED ENV{VCToolsRedistDir} AND EXISTS "$ENV{VCToolsRedistDir}x64/Microsoft.VC143.CRT/${crt_dll}")
    list(APPEND TYPEMATE_CRT_DLLS "$ENV{VCToolsRedistDir}x64/Microsoft.VC143.CRT/${crt_dll}")
  elseif(EXISTS "C:/Windows/Sysnative/${crt_dll}")
    list(APPEND TYPEMATE_CRT_DLLS "C:/Windows/Sysnative/${crt_dll}")
  elseif(EXISTS "C:/Windows/System32/${crt_dll}")
    list(APPEND TYPEMATE_CRT_DLLS "C:/Windows/System32/${crt_dll}")
  else()
    message(FATAL_ERROR "MSVC runtime ${crt_dll} not found; users without the VC++ redistributable would crash at launch")
  endif()
endforeach()
install(FILES ${TYPEMATE_CRT_DLLS}
  DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
