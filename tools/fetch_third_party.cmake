# fetch_third_party.cmake — idempotent vendoring of all C++ dependencies.
#
# Usage (from the repository root):
#   cmake -P tools/fetch_third_party.cmake
#   cmake -DURPC_TP_CHECK_ONLY=ON -P tools/fetch_third_party.cmake   # verify only
#
# Contract: specs/002-vendor-third-party/contracts/fetch-command.md
# Manifest: third_party/versions.cmake (single source of truth)

cmake_minimum_required(VERSION 3.21)

get_filename_component(URPC_REPO "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
include("${URPC_REPO}/third_party/versions.cmake")

set(URPC_TP_DEPS libuv nghttp2 protobuf abseil googletest benchmark)

set(URPC_FETCHED 0)
set(URPC_SKIPPED 0)
set(URPC_FAILED 0)

function(urpc_marker_path OUT NAME)
  set(${OUT} "${URPC_REPO}/third_party/${NAME}/.urpc-version" PARENT_SCOPE)
endfunction()

function(urpc_expected_marker OUT VER SHA)
  set(${OUT} "version=${VER}\nsha256=${SHA}\n" PARENT_SCOPE)
endfunction()

foreach(URPC_NAME IN LISTS URPC_TP_DEPS)
  string(TOUPPER "${URPC_NAME}" URPC_PREFIX)
  set(URPC_VER "${URPC_TP_${URPC_PREFIX}_VERSION}")
  set(URPC_URL "${URPC_TP_${URPC_PREFIX}_URL}")
  set(URPC_SHA "${URPC_TP_${URPC_PREFIX}_SHA256}")
  set(URPC_DIR "${URPC_REPO}/third_party/${URPC_NAME}")
  urpc_marker_path(URPC_MARKER "${URPC_NAME}")
  urpc_expected_marker(URPC_EXPECTED "${URPC_VER}" "${URPC_SHA}")

  # ---- state: MATCHED / MISMATCH / MISSING -------------------------------
  set(URPC_STATE "MISSING")
  if(EXISTS "${URPC_MARKER}")
    file(READ "${URPC_MARKER}" URPC_ACTUAL)
    if(URPC_ACTUAL STREQUAL URPC_EXPECTED)
      set(URPC_STATE "MATCHED")
    else()
      set(URPC_STATE "MISMATCH")
    endif()
  endif()

  if(URPC_STATE STREQUAL "MATCHED")
    math(EXPR URPC_SKIPPED "${URPC_SKIPPED} + 1")
    message(STATUS "[fetch] ${URPC_NAME} ${URPC_VER}: skipped (already vendored)")
    continue()
  endif()

  if(URPC_STATE STREQUAL "MISMATCH")
    message(STATUS "[fetch] ${URPC_NAME}: stale/incomplete marker — refetching")
    file(REMOVE_RECURSE "${URPC_DIR}")
  endif()

  if(URPC_TP_CHECK_ONLY)
    math(EXPR URPC_FAILED "${URPC_FAILED} + 1")
    message(STATUS "[fetch] ${URPC_NAME} ${URPC_VER}: NOT vendored (check-only mode)")
    continue()
  endif()

  # ---- download (cached tarball first) -----------------------------------
  set(URPC_DL_DIR "${URPC_REPO}/third_party/.downloads")
  set(URPC_TARBALL "${URPC_DL_DIR}/${URPC_NAME}-${URPC_VER}.tar.gz")
  file(MAKE_DIRECTORY "${URPC_DL_DIR}")

  set(URPC_NEED_DL TRUE)
  if(EXISTS "${URPC_TARBALL}")
    file(SHA256 "${URPC_TARBALL}" URPC_GOT)
    if(URPC_GOT STREQUAL URPC_SHA)
      set(URPC_NEED_DL FALSE)
    else()
      file(REMOVE "${URPC_TARBALL}")
    endif()
  endif()

  if(URPC_NEED_DL)
    message(STATUS "[fetch] ${URPC_NAME} ${URPC_VER}: downloading")
    file(DOWNLOAD "${URPC_URL}" "${URPC_TARBALL}" STATUS URPC_DL_STATUS)
    list(GET URPC_DL_STATUS 0 URPC_DL_RC)
    if(NOT URPC_DL_RC EQUAL 0)
      # fall back to system curl (handles flaky redirect chains better)
      find_program(URPC_CURL curl)
      if(URPC_CURL)
        file(REMOVE "${URPC_TARBALL}")
        execute_process(
          COMMAND "${URPC_CURL}" -L --retry 3 --silent --show-error
                  --output "${URPC_TARBALL}" "${URPC_URL}"
          RESULT_VARIABLE URPC_CURL_RC)
        set(URPC_DL_RC "${URPC_CURL_RC}")
      endif()
    endif()
    if(NOT URPC_DL_RC EQUAL 0)
      math(EXPR URPC_FAILED "${URPC_FAILED} + 1")
      message(STATUS "[fetch] ${URPC_NAME}: download FAILED (${URPC_URL}): ${URPC_DL_STATUS}")
      continue()
    endif()
  endif()

  # ---- verify -------------------------------------------------------------
  file(SHA256 "${URPC_TARBALL}" URPC_GOT)
  if(NOT URPC_GOT STREQUAL URPC_SHA)
    math(EXPR URPC_FAILED "${URPC_FAILED} + 1")
    message(STATUS "[fetch] ${URPC_NAME}: sha256 MISMATCH (expected ${URPC_SHA}, got ${URPC_GOT}); tarball kept at ${URPC_TARBALL}")
    continue()
  endif()

  # ---- extract (strip archive top-level dir) ------------------------------
  # NOTE: file(ARCHIVE_EXTRACT) is best-effort and does not fail on a
  # truncated archive — use `cmake -E tar` through execute_process so a
  # non-zero result is observable, and verify a sentinel afterwards.
  set(URPC_STAGE "${URPC_REPO}/third_party/.extract-${URPC_NAME}")
  file(REMOVE_RECURSE "${URPC_STAGE}")
  file(MAKE_DIRECTORY "${URPC_STAGE}")
  execute_process(
    COMMAND ${CMAKE_COMMAND} -E tar xf "${URPC_TARBALL}"
    WORKING_DIRECTORY "${URPC_STAGE}"
    RESULT_VARIABLE URPC_TAR_RC)
  if(NOT URPC_TAR_RC EQUAL 0)
    math(EXPR URPC_FAILED "${URPC_FAILED} + 1")
    message(STATUS "[fetch] ${URPC_NAME}: extract FAILED (rc=${URPC_TAR_RC}, truncated/corrupt archive)")
    file(REMOVE_RECURSE "${URPC_STAGE}")
    continue()
  endif()
  file(GLOB URPC_TOPS RELATIVE "${URPC_STAGE}" "${URPC_STAGE}/*")
  list(LENGTH URPC_TOPS URPC_TOPS_N)
  if(NOT URPC_TOPS_N EQUAL 1)
    math(EXPR URPC_FAILED "${URPC_FAILED} + 1")
    message(STATUS "[fetch] ${URPC_NAME}: unexpected archive layout (${URPC_TOPS_N} top-level entries)")
    file(REMOVE_RECURSE "${URPC_STAGE}")
    continue()
  endif()
  if(NOT EXISTS "${URPC_STAGE}/${URPC_TOPS}/CMakeLists.txt")
    math(EXPR URPC_FAILED "${URPC_FAILED} + 1")
    message(STATUS "[fetch] ${URPC_NAME}: sentinel CMakeLists.txt missing after extract")
    file(REMOVE_RECURSE "${URPC_STAGE}")
    continue()
  endif()
  file(REMOVE_RECURSE "${URPC_DIR}")
  file(RENAME "${URPC_STAGE}/${URPC_TOPS}" "${URPC_DIR}")
  file(REMOVE_RECURSE "${URPC_STAGE}")
  file(REMOVE "${URPC_TARBALL}")

  # ---- marker --------------------------------------------------------------
  file(WRITE "${URPC_MARKER}" "${URPC_EXPECTED}")
  math(EXPR URPC_FETCHED "${URPC_FETCHED} + 1")
  message(STATUS "[fetch] ${URPC_NAME} ${URPC_VER}: vendored (sha256 ok)")
endforeach()

message(STATUS "[fetch] summary: fetched=${URPC_FETCHED} skipped=${URPC_SKIPPED} failed=${URPC_FAILED}")

# keep third_party/ pristine on success: drop the (empty) download cache
if(URPC_FAILED EQUAL 0 AND EXISTS "${URPC_REPO}/third_party/.downloads")
  file(GLOB_RECURSE URPC_DL_LEFTOVERS "${URPC_REPO}/third_party/.downloads/*")
  if(NOT URPC_DL_LEFTOVERS)
    file(REMOVE_RECURSE "${URPC_REPO}/third_party/.downloads")
  endif()
endif()

if(URPC_FAILED GREATER 0)
  message(FATAL_ERROR
    "urpc: third-party vendoring incomplete "
    "(fetched=${URPC_FETCHED} skipped=${URPC_SKIPPED} failed=${URPC_FAILED}). "
    "Re-run: cmake -P tools/fetch_third_party.cmake")
endif()
