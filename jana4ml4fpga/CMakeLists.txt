cmake_minimum_required(VERSION 3.19)

project(JANA4ML4FPGA VERSION 0.0.0)

# Make C++17 a default
if(NOT "${CMAKE_CXX_STANDARD}")
    set(CMAKE_CXX_STANDARD 20)  # ROOT 6.40 and JANA2 2026.x are C++20
endif()
message(STATUS "CMAKE_CXX_STANDARD = ${CMAKE_CXX_STANDARD}")

# Enable -fPIC for all targets
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(CMAKE_BUILD_TYPE Debug)

# Find packages
# ROOT must be pre-installed (system package, conda or thisroot.sh)

include(cmake/vdt_stub.cmake)      # Stub for ROOT installations built with vdt when vdt is absent

find_package(ROOT REQUIRED)

# Fetch and build missing small dependencies (JANA2, spdlog, fmt) at configure time.
# Does nothing for dependencies that are already installed.
option(FETCH_DEPENDENCIES "Download and build missing dependencies (JANA2, spdlog, fmt) with FetchContent" ON)
if(FETCH_DEPENDENCIES)
    include(cmake/fetch_dependencies.cmake)
else()
    message(WARNING "${CMAKE_PROJECT_NAME}: FETCH_DEPENDENCIES=OFF - JANA2 comes from the environment and does NOT carry this project's patches. The chain needs the unfolder fixes released in JANA2 v2026.03.01, and older builds segfault on the first block (see docs/jana2-unfolder-bug.md).")
endif()

find_package(JANA REQUIRED)
find_package(spdlog REQUIRED)
find_package(fmt REQUIRED)

# Install to the top directory by default
if( ${CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT} )
    set(CMAKE_INSTALL_PREFIX ${CMAKE_SOURCE_DIR}/install CACHE PATH "Install in top directory by default" FORCE)
endif()

set(PLUGIN_OUTPUT_DIRECTORY "${CMAKE_INSTALL_PREFIX}/plugins")
set(INCLUDE_OUTPUT_DIRECTORY "${CMAKE_INSTALL_PREFIX}/include")
set(LIBRARY_OUTPUT_DIRECTORY "${CMAKE_INSTALL_PREFIX}/lib")
set(PROGRAM_OUTPUT_DIRECTORY "${CMAKE_INSTALL_PREFIX}/bin")

message(STATUS "${CMAKE_PROJECT_NAME}: CMAKE_INSTALL_PREFIX    : ${CMAKE_INSTALL_PREFIX}")
message(STATUS "${CMAKE_PROJECT_NAME}: PLUGIN_OUTPUT_DIRECTORY : ${PLUGIN_OUTPUT_DIRECTORY}")
message(STATUS "${CMAKE_PROJECT_NAME}: INCLUDE_OUTPUT_DIRECTORY: ${INCLUDE_OUTPUT_DIRECTORY}")
message(STATUS "${CMAKE_PROJECT_NAME}: LIBRARY_OUTPUT_DIRECTORY: ${LIBRARY_OUTPUT_DIRECTORY}")
message(STATUS "${CMAKE_PROJECT_NAME}: PROGRAM_OUTPUT_DIRECTORY: ${PROGRAM_OUTPUT_DIRECTORY}")

# Installed binaries and plugins must load the JANA2 that was built with this
# project's patches (cmake/patches/, see docs/jana2-unfolder-bug.md), not one that
# happens to sit earlier on LD_LIBRARY_PATH - the EIC docker images ship their own
# libJANA.so, and loading it reintroduces the segfault the patches remove.
# $ORIGIN/../lib resolves to <prefix>/lib for both <prefix>/bin and <prefix>/plugins,
# which is where fetch_dependencies.cmake installs libJANA.so.
# Set before any target is created: targets capture this value when they are defined.
set(CMAKE_INSTALL_RPATH "$ORIGIN/../lib")

# Emit DT_RPATH instead of the modern default DT_RUNPATH. The dynamic linker searches
# DT_RPATH *before* LD_LIBRARY_PATH but DT_RUNPATH *after* it, so with the default an
# environment that puts another JANA2 on LD_LIBRARY_PATH still wins - which is exactly
# the docker-image case this guards against.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    add_link_options("LINKER:--disable-new-dtags")
endif()

# JANA2
message(STATUS "${CMAKE_PROJECT_NAME}: JANA2 cmake   : ${JANA_DIR}")
message(STATUS "${CMAKE_PROJECT_NAME}: JANA2 includes: ${JANA_INCLUDE_DIR}")
message(STATUS "${CMAKE_PROJECT_NAME}: JANA2 library : ${JANA_LIBRARY}")

# CERN ROOT
message(STATUS "${CMAKE_PROJECT_NAME}: ROOT version  : ${ROOT_VERSION}")
message(STATUS "${CMAKE_PROJECT_NAME}: ROOT libraries: ${ROOT_LIBRARIES}")


# Add CMake additional functionality:
include(cmake/print_functions.cmake)                        # Helpers to print fancy headers, file names, etc
include(cmake/print_subdirectory_tree.cmake)                # Prints processed subdirectories
include(cmake/jana_plugin.cmake)                            # Add common settings for plugins
list (APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)   # Find Find<Modules>.cmake


# Add src as a global include directory
include_directories(${CMAKE_SOURCE_DIR}/src)

# Libraries are separate objects. This include directory lets code use
# #include <evio_sro_parser/SroData.h> instead of <libraries/evio_sro_parser/SroData.h>.
include_directories(${CMAKE_SOURCE_DIR}/src/libraries)

#Add clang sanitizers
#if (CMAKE_CXX_COMPILER_ID MATCHES "Clang")
#    # Enable sanitizers
#    message(STATUS "Clang sanitizers are enabled")
#    set(SANITIZE_FLAGS "-fsanitize=address,undefined")
#    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${SANITIZE_FLAGS}")
#    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${SANITIZE_FLAGS}")
#endif()

# set(CMAKE_CXX_LINK_FLAGS "${CMAKE_CXX_LINK_FLAGS} -latomic")

# ---------------------------------------------------------------------------
print_grand_header("    B U I L D   J A N A 4 M L 4 F P G A   P A R T S    ")
# ---------------------------------------------------------------------------

add_subdirectory(src/libraries)
add_subdirectory(src/services)
add_subdirectory(src/plugins)
add_subdirectory(src/executables)

# Print what we had built
print_header("CMake processed subdirectories:")
print_subdirectory_tree()
message(STATUS "\n-------------------------------")