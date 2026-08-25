# Downloads missing dependencies at configure time using FetchContent.
#
# ROOT is NOT handled here: it is a heavy dependency and must be pre-installed
# (system package, conda, or sourced thisroot.sh).
#
# fmt and spdlog are fetched only when find_package cannot find them, so
# pre-installed setups (e.g. gluon nodes, docker) keep using their own.
#
# JANA2 is the exception: it is always built here from a pinned revision, because
# this project needs specific fixes and a stable baseline. The JANA2 section below
# explains why and how to override it. It is configured, built and installed into
# ${CMAKE_BINARY_DIR}/deps/jana2 at configure time, then consumed through its
# installed JANAConfig.cmake (JANA_DIR, JANA_INCLUDE_DIR, JANA_LIB, ...) exactly as
# a pre-installed JANA2 would be.

include(FetchContent)

# ----------------------------------- fmt ------------------------------------
find_package(fmt QUIET)
if(fmt_FOUND)
    message(STATUS "${CMAKE_PROJECT_NAME}: fmt found: ${fmt_DIR}")
else()
    message(STATUS "${CMAKE_PROJECT_NAME}: fmt NOT found. Fetching it with FetchContent")
    FetchContent_Declare(fmt
            URL https://github.com/fmtlib/fmt/archive/refs/tags/10.2.1.tar.gz
            OVERRIDE_FIND_PACKAGE)
    FetchContent_MakeAvailable(fmt)
endif()

# ---------------------------------- spdlog ----------------------------------
find_package(spdlog QUIET)
if(spdlog_FOUND)
    message(STATUS "${CMAKE_PROJECT_NAME}: spdlog found: ${spdlog_DIR}")
else()
    message(STATUS "${CMAKE_PROJECT_NAME}: spdlog NOT found. Fetching it with FetchContent")
    set(SPDLOG_FMT_EXTERNAL ON CACHE BOOL "spdlog uses external fmt" FORCE)
    FetchContent_Declare(spdlog
            URL https://github.com/gabime/spdlog/archive/refs/tags/v1.14.1.tar.gz
            OVERRIDE_FIND_PACKAGE)
    FetchContent_MakeAvailable(spdlog)
endif()

# ---------------------------------- JANA2 -----------------------------------
# Unlike fmt and spdlog above, JANA2 is ALWAYS built here, from the pinned revision
# with the patches in cmake/patches/, even when the environment already provides one.
# Two reasons:
#   - Correctness. The timeslice -> frame chain needs the unfolder fixes released in
#     JANA2 v2026.03.01; against anything older it segfaults on the first block or
#     hangs once the Timeslice pool drains (see docs/jana2-unfolder-bug.md). Docker
#     images still ship older JANA2 builds.
#   - Reproducibility. This project measures throughput across runs and machines,
#     so JANA2 must be the same code every time. A JANA2 that arrives with a docker
#     image is an uncontrolled variable: the image can be rebuilt underneath a
#     measurement series and silently move the baseline.
# ML4_USE_SYSTEM_JANA2=ON links whatever the environment provides instead. Use it for
# debugging only - the chain may crash, and measurements taken with it are not
# comparable to any other run.
option(ML4_USE_SYSTEM_JANA2 "Link the environment's JANA2 instead of building the pinned, patched one" OFF)

set(JANA2_VERSION "v2026.03.01" CACHE STRING "JANA2 git tag/SHA to fetch and build")
set(JANA2_SOURCE_DIR ${CMAKE_BINARY_DIR}/deps/jana2-src)
set(JANA2_BUILD_DIR ${CMAKE_BINARY_DIR}/deps/jana2-build)
set(JANA2_INSTALL_DIR ${CMAKE_BINARY_DIR}/deps/jana2)

# No patches are applied at present: v2026.03.01 carries the unfolder fixes this
# chain needs. patches/jana2-clear-outputs-off-mutex.patch is kept but NOT listed,
# because it measured as no change on this chain (docs/jana2-unfolder-bug.md
# records the numbers). Add it back to this list to re-test it - the machinery
# below applies whatever the list names.
set(ML4_JANA2_PATCHES "")

if(ML4_USE_SYSTEM_JANA2)
    find_package(JANA REQUIRED)
    message(WARNING "${CMAKE_PROJECT_NAME}: ML4_USE_SYSTEM_JANA2=ON - linking JANA2 at ${JANA_DIR} instead of the pinned patched build. The chain may segfault, and throughput numbers from this build are not comparable to other runs.")
else()
    # What the copy in this build tree must be built from: the pinned revision plus
    # the exact content of every patch. Editing a patch or moving the pin changes this
    # string, which forces a clean refetch and rebuild - otherwise a stale deps/jana2
    # would be reused and the build would quietly disagree with the sources.
    set(_jana2_stamp_expected "jana2=${JANA2_VERSION}")
    foreach(_patch IN LISTS ML4_JANA2_PATCHES)
        file(MD5 ${CMAKE_CURRENT_LIST_DIR}/patches/${_patch} _patch_md5)
        string(APPEND _jana2_stamp_expected " ${_patch}=${_patch_md5}")
    endforeach()

    if(ML4_JANA2_PATCHES)
        string(REPLACE ";" ", " _jana2_patch_summary "patches: ${ML4_JANA2_PATCHES}")
    else()
        set(_jana2_patch_summary "no patches")
    endif()

    set(_jana2_stamp_file ${JANA2_INSTALL_DIR}/ml4-jana2-stamp.txt)
    set(_jana2_stamp_actual "")
    if(EXISTS ${_jana2_stamp_file})
        file(READ ${_jana2_stamp_file} _jana2_stamp_actual)
    endif()
endif()

if(NOT ML4_USE_SYSTEM_JANA2 AND _jana2_stamp_actual STREQUAL _jana2_stamp_expected)
    message(STATUS "${CMAKE_PROJECT_NAME}: JANA2 ${JANA2_VERSION} (${_jana2_patch_summary}) already built in ${JANA2_INSTALL_DIR}")
elseif(NOT ML4_USE_SYSTEM_JANA2)
    message(STATUS "${CMAKE_PROJECT_NAME}: building JANA2 ${JANA2_VERSION} (${_jana2_patch_summary}) into ${JANA2_INSTALL_DIR}")

    # Start from a clean tree. Patches apply to pristine sources, so reusing a tree
    # that already carries an older patch set is not safe.
    file(REMOVE_RECURSE
            ${JANA2_SOURCE_DIR}
            ${JANA2_BUILD_DIR}
            ${JANA2_INSTALL_DIR}
            ${CMAKE_BINARY_DIR}/deps/jana2-populate-bin
            ${CMAKE_BINARY_DIR}/deps/jana2-populate-subbuild)

    # Download at configure time (direct form of FetchContent_Populate: download only,
    # no add_subdirectory - JANA2 must be *installed* for its JANAConfig.cmake to work)
    FetchContent_Populate(jana2_download
            GIT_REPOSITORY https://github.com/JeffersonLab/JANA2.git
            GIT_TAG ${JANA2_VERSION}
            GIT_SHALLOW FALSE  # SHA pins cannot be fetched shallowly
            SOURCE_DIR ${JANA2_SOURCE_DIR}
            BINARY_DIR ${CMAKE_BINARY_DIR}/deps/jana2-populate-bin
            SUBBUILD_DIR ${CMAKE_BINARY_DIR}/deps/jana2-populate-subbuild)

    # Patch: rootcling of ROOT >= 6.32 fails to generate dictionaries of the
    # janaview (GUI debugging) and JTestRoot (test) plugins. Neither is needed
    # by this project, so drop them from the JANA2 build.
    file(READ ${JANA2_SOURCE_DIR}/src/plugins/CMakeLists.txt _jana2_plugins_cml)
    if(NOT _jana2_plugins_cml MATCHES "disabled by jana4ml4fpga")
        string(REPLACE "add_subdirectory(janaview)"
                "# add_subdirectory(janaview)  # disabled by jana4ml4fpga (rootcling incompatibility)"
                _jana2_plugins_cml "${_jana2_plugins_cml}")
        string(REPLACE "add_subdirectory(JTestRoot)"
                "# add_subdirectory(JTestRoot)  # disabled by jana4ml4fpga (rootcling incompatibility)"
                _jana2_plugins_cml "${_jana2_plugins_cml}")
        file(WRITE ${JANA2_SOURCE_DIR}/src/plugins/CMakeLists.txt "${_jana2_plugins_cml}")
    endif()

    # Applies one patch file from cmake/patches/ to the JANA2 source tree. A patch that
    # no longer applies is a hard error, not a warning: it means JANA2_VERSION moved and
    # the patch either landed upstream (drop it from ML4_JANA2_PATCHES) or needs porting.
    # Silently continuing would produce a JANA2 that is not what the stamp claims.
    function(_ml4_apply_jana2_patch patch_name)
        find_package(Git QUIET)
        if(NOT GIT_EXECUTABLE)
            set(GIT_EXECUTABLE git)
        endif()
        set(_patch_file ${CMAKE_CURRENT_LIST_DIR}/patches/${patch_name})
        message(STATUS "${CMAKE_PROJECT_NAME}: applying JANA2 patch ${patch_name}")
        execute_process(
                COMMAND ${GIT_EXECUTABLE} -C ${JANA2_SOURCE_DIR} apply ${_patch_file}
                RESULT_VARIABLE _patch_result)
        if(_patch_result)
            message(FATAL_ERROR "Failed to apply JANA2 patch: ${_patch_file}")
        endif()
    endfunction()

    foreach(_patch IN LISTS ML4_JANA2_PATCHES)
        _ml4_apply_jana2_patch(${_patch})
    endforeach()

    # Configure, build and install JANA2. Reaching this point means the stamp did not
    # match, so there is nothing to reuse.
    execute_process(
            COMMAND ${CMAKE_COMMAND}
                -S ${JANA2_SOURCE_DIR}
                -B ${JANA2_BUILD_DIR}
                -DCMAKE_INSTALL_PREFIX=${JANA2_INSTALL_DIR}
                -DCMAKE_BUILD_TYPE=Release
                -DCMAKE_CXX_STANDARD=${CMAKE_CXX_STANDARD}
                -DCMAKE_POSITION_INDEPENDENT_CODE=ON
                -DCMAKE_POLICY_VERSION_MINIMUM=3.5
                -DCMAKE_PROJECT_INCLUDE=${CMAKE_SOURCE_DIR}/cmake/vdt_stub.cmake
                -DUSE_ROOT=On
                -DUSE_PODIO=Off
                -DUSE_ZEROMQ=Off
                -DUSE_PYTHON=Off
            RESULT_VARIABLE JANA2_CONFIGURE_RESULT)
    if(JANA2_CONFIGURE_RESULT)
        message(FATAL_ERROR "JANA2 configure step failed (see errors above)")
    endif()

    include(ProcessorCount)
    ProcessorCount(NPROC)
    if(NPROC EQUAL 0)
        set(NPROC 4)
    endif()

    execute_process(
            COMMAND ${CMAKE_COMMAND} --build ${JANA2_BUILD_DIR} --parallel ${NPROC}
            RESULT_VARIABLE JANA2_BUILD_RESULT)
    if(JANA2_BUILD_RESULT)
        message(FATAL_ERROR "JANA2 build step failed (see errors above)")
    endif()

    execute_process(
            COMMAND ${CMAKE_COMMAND} --install ${JANA2_BUILD_DIR}
            RESULT_VARIABLE JANA2_INSTALL_RESULT)
    if(JANA2_INSTALL_RESULT)
        message(FATAL_ERROR "JANA2 install step failed (see errors above)")
    endif()

    # Written last: a stamp exists only for a copy that built and installed cleanly,
    # so an interrupted build is refetched rather than reused.
    file(WRITE ${_jana2_stamp_file} "${_jana2_stamp_expected}")
endif()

if(NOT ML4_USE_SYSTEM_JANA2)
    # Drop any JANA_DIR the cache already holds. A build tree configured before this
    # policy existed (or by hand) can carry JANA_DIR pointing at the environment's
    # JANA2, and config-mode find_package short-circuits on a valid <Pkg>_DIR: PATHS
    # and NO_DEFAULT_PATH constrain the search, they do not override that cache entry.
    # Without this the build compiles the patched copy and then links the other one.
    unset(JANA_DIR CACHE)

    # NO_DEFAULT_PATH: the pinned patched copy must win even when the environment
    # provides its own JANA2 on the default search paths.
    find_package(JANA REQUIRED PATHS ${JANA2_INSTALL_DIR} NO_DEFAULT_PATH)
    message(STATUS "${CMAKE_PROJECT_NAME}: JANA2 in use: ${JANA_DIR}")
endif()

# Self-contained install: ship the JANA2 that was built here inside this project's
# prefix, so libJANA.so lands in install/lib and JANA's own plugins in
# install/plugins. Together with CMAKE_INSTALL_RPATH ($ORIGIN/../lib, set in the
# top-level CMakeLists.txt) this makes the installed chain load its own patched
# JANA2 without any LD_LIBRARY_PATH setup, and without a path into the build tree.
#
# Keying on JANA_DIR pointing inside the build tree skips these rules under
# ML4_USE_SYSTEM_JANA2=ON, where copying the environment's JANA2 would be wrong.
if(DEFINED JANA_DIR AND JANA_DIR MATCHES "^${CMAKE_BINARY_DIR}/deps/jana2")
    set(_ml4_fetched_jana2 ${CMAKE_BINARY_DIR}/deps/jana2)
    install(DIRECTORY ${_ml4_fetched_jana2}/lib/     DESTINATION lib     USE_SOURCE_PERMISSIONS)
    install(DIRECTORY ${_ml4_fetched_jana2}/lib64/   DESTINATION lib64   USE_SOURCE_PERMISSIONS OPTIONAL)
    install(DIRECTORY ${_ml4_fetched_jana2}/bin/     DESTINATION bin     USE_SOURCE_PERMISSIONS OPTIONAL)
    install(DIRECTORY ${_ml4_fetched_jana2}/include/ DESTINATION include                        OPTIONAL)
    install(DIRECTORY ${_ml4_fetched_jana2}/plugins/ DESTINATION plugins USE_SOURCE_PERMISSIONS OPTIONAL)
endif()
