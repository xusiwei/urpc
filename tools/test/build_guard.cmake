# build_guard.cmake — contract test for the vendoring gate
# (specs/002-vendor-third-party/contracts/build-guard.md)
#
# Temporarily hides third_party/libuv, runs a fresh configure and asserts it
# FAILS with the fetch guidance; restores the directory afterwards.

cmake_minimum_required(VERSION 3.21)

get_filename_component(URPC_REPO "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(URPC_TP "${URPC_REPO}/third_party")
set(URPC_TMP "${URPC_REPO}/build/vendor-tests/build-guard-tmp")

set(URPC_GUIDANCE "cmake -P tools/fetch_third_party.cmake")

# ---- hide libuv -----------------------------------------------------------
file(RENAME "${URPC_TP}/libuv" "${URPC_TP}/libuv.hidden-by-guard-test")

# ---- configure must fail with guidance ------------------------------------
execute_process(
  COMMAND ${CMAKE_COMMAND} -S "${URPC_REPO}" -B "${URPC_TMP}"
          -G "${CMAKE_GENERATOR}"
          -DURPC_BUILD_TESTS=OFF -DURPC_BUILD_BENCH=OFF
          -DURPC_BUILD_EXAMPLES=OFF -DURPC_BUILD_INTEROP=OFF
  OUTPUT_VARIABLE URPC_OUT
  ERROR_VARIABLE URPC_OUT
  RESULT_VARIABLE URPC_RC
  TIMEOUT 120)

# ---- restore FIRST, assert afterwards --------------------------------------
file(RENAME "${URPC_TP}/libuv.hidden-by-guard-test" "${URPC_TP}/libuv")
file(REMOVE_RECURSE "${URPC_TMP}")

set(URPC_ERR "")
if(NOT URPC_RC EQUAL 0)
  # fine — but the output MUST name the dependency and the guidance command
  if(NOT URPC_OUT MATCHES "libuv")
    string(APPEND URPC_ERR "error text does not name 'libuv'; ")
  endif()
  if(NOT URPC_OUT MATCHES "cmake -P tools/fetch_third_party\\.cmake")
    string(APPEND URPC_ERR "error text lacks fetch guidance '${URPC_GUIDANCE}'; ")
  endif()
else()
  string(APPEND URPC_ERR "configure unexpectedly SUCCEEDED without libuv vendored; ")
endif()

if(NOT EXISTS "${URPC_TP}/libuv/.urpc-version")
  string(APPEND URPC_ERR "libuv was not restored properly; ")
endif()

if(URPC_ERR STREQUAL "")
  message(STATUS "build_guard: PASS (configure failed with guidance, libuv restored)")
else()
  message(FATAL_ERROR "build_guard: FAIL — ${URPC_ERR}")
endif()
