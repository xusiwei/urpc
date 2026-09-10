# urpc-deps.cmake — consume vendored third-party dependencies.
#
# Policy (spec 002-vendor-third-party; constitution Principle V):
#   * every C++ dependency is vendored under third_party/<name>/ by
#     `cmake -P tools/fetch_third_party.cmake` (pinned in
#     third_party/versions.cmake — single reviewed source of truth)
#   * configure NEVER touches the network; missing/stale deps are a hard
#     error with fetch guidance (contracts/build-guard.md)
#   * exposed target names are stable: uv_a / nghttp2_static / urpc_upb /
#     protoc / GTest::gtest / benchmark::benchmark

include("${CMAKE_CURRENT_SOURCE_DIR}/third_party/versions.cmake")

# ---------------------------------------------------------------------------
# guard: a dependency is "vendored" iff its marker matches the manifest
# ---------------------------------------------------------------------------
function(urpc_tp_require NAME)
  string(TOUPPER "${NAME}" P)
  set(ver "${URPC_TP_${P}_VERSION}")
  set(sha "${URPC_TP_${P}_SHA256}")
  set(marker "${CMAKE_CURRENT_SOURCE_DIR}/third_party/${NAME}/.urpc-version")
  set(expected "version=${ver}\nsha256=${sha}\n")
  set(ok FALSE)
  if(EXISTS "${marker}")
    file(READ "${marker}" actual)
    if(actual STREQUAL expected)
      set(ok TRUE)
    endif()
  endif()
  if(NOT ok)
    message(FATAL_ERROR
      "urpc: third-party dependency '${NAME}' (version ${ver}) is not vendored.\n"
      "      Run:  cmake -P tools/fetch_third_party.cmake\n"
      "      (from the repository root; requires network access)")
  endif()
endfunction()

# ---------------------------------------------------------------------------
# libuv
# ---------------------------------------------------------------------------
urpc_tp_require(libuv)
set(LIBUV_BUILD_SHARED OFF CACHE INTERNAL "")
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/third_party/libuv"
                 "${CMAKE_BINARY_DIR}/third_party/libuv")
if(TARGET libuv::libuv)
  set(URPC_LIBUV_TARGET libuv::libuv)
elseif(TARGET uv_a)
  set(URPC_LIBUV_TARGET uv_a)
else()
  set(URPC_LIBUV_TARGET uv)
endif()

# ---------------------------------------------------------------------------
# nghttp2
# ---------------------------------------------------------------------------
urpc_tp_require(nghttp2)
set(ENABLE_SHARED_LIB OFF CACHE INTERNAL "")
set(ENABLE_STATIC_LIB ON  CACHE INTERNAL "")
set(ENABLE_BIN         OFF CACHE INTERNAL "")
set(ENABLE_EXAMPLES    OFF CACHE INTERNAL "")
set(ENABLE_TESTS       OFF CACHE INTERNAL "")
set(ENABLE_DOC         OFF CACHE INTERNAL "")
set(ENABLE_HTTP3       OFF CACHE INTERNAL "")
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/third_party/nghttp2"
                 "${CMAKE_BINARY_DIR}/third_party/nghttp2")
if(TARGET nghttp2_static)
  set(URPC_NGHTTP2_TARGET nghttp2_static)
else()
  set(URPC_NGHTTP2_TARGET nghttp2)
endif()

# ---------------------------------------------------------------------------
# upb runtime (C subset of the vendored protobuf tree; no abseil,
# no libprotobuf). Typed access comes from protoc --upb_out generated code.
# ---------------------------------------------------------------------------
urpc_tp_require(protobuf)
set(URPC_PROTOBUF_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/protobuf")

file(GLOB_RECURSE URPC_UPB_SOURCES
  "${URPC_PROTOBUF_DIR}/upb/*.c")
# drop tests/fuzzers/conformance/build-generated copies and reflection
# (reflection needs generated descriptor tables which we do not use)
list(FILTER URPC_UPB_SOURCES EXCLUDE REGEX "/(test|tests|fuzz|fuzzer|conformance|cmake|benchmark|benchmarks|reflection|json|text|util)/")
list(FILTER URPC_UPB_SOURCES EXCLUDE REGEX "(_test|_tests|_fuzz|_fuzzer)\\.c$")
list(FILTER URPC_UPB_SOURCES EXCLUDE REGEX "(^|/)test_[^/]*\\.c$")

# utf8_range (upb's UTF-8 validation) — vendored in the protobuf tree
list(APPEND URPC_UPB_SOURCES
  "${URPC_PROTOBUF_DIR}/third_party/utf8_range/utf8_range.c")

add_library(urpc_upb STATIC ${URPC_UPB_SOURCES})
target_include_directories(urpc_upb PUBLIC
  "${URPC_PROTOBUF_DIR}"
  "${URPC_PROTOBUF_DIR}/third_party/utf8_range")
target_compile_options(urpc_upb PRIVATE
  $<$<C_COMPILER_ID:GNU,Clang,AppleClang>:-Wno-declaration-after-statement>)

# ---------------------------------------------------------------------------
# host protoc with --upb_out support (protobuf >= 23):
# use a usable system protoc when present, otherwise build from vendored
# source (protobuf + its pinned abseil). No downloads in either path.
# ---------------------------------------------------------------------------
function(_urpc_protoc_version PROTOC_BIN OUT_VAR)
  execute_process(COMMAND "${PROTOC_BIN}" --version
    OUTPUT_VARIABLE ver OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET RESULT_VARIABLE rc)
  if(NOT rc EQUAL 0)
    set(${OUT_VAR} 0 PARENT_SCOPE)
    return()
  endif()
  string(REGEX MATCH "[0-9]+\\.[0-9]+(\\.[0-9]+)?" num "${ver}")
  string(REGEX MATCH "^[0-9]+" major "${num}")
  set(${OUT_VAR} "${major}" PARENT_SCOPE)
endfunction()

if(URPC_PROTOC_EXECUTABLE AND NOT URPC_PROTOC_EXECUTABLE MATCHES "^\\\$<TARGET_FILE" AND NOT EXISTS "${URPC_PROTOC_EXECUTABLE}")
  unset(URPC_PROTOC_EXECUTABLE CACHE)
endif()
if(NOT URPC_PROTOC_EXECUTABLE)
  find_program(URPC_SYSTEM_PROTOC protoc)
  set(URPC_PROTOC_MAJOR 0)
  if(URPC_SYSTEM_PROTOC)
    _urpc_protoc_version("${URPC_SYSTEM_PROTOC}" URPC_PROTOC_MAJOR)
  endif()
  if(URPC_PROTOC_MAJOR GREATER_EQUAL 23)
    set(URPC_PROTOC_EXECUTABLE "${URPC_SYSTEM_PROTOC}" CACHE FILEPATH
        "protoc used for --upb_out generation")
  else()
    # build host protoc in-tree from vendored sources; protobuf's cmake
    # reuses pre-existing absl:: targets (its cmake/abseil-cpp.cmake)
    urpc_tp_require(abseil)
    set(ABSL_ENABLE_TESTING OFF CACHE INTERNAL "")
    set(ABSL_PROPAGATE_CXX_STD ON CACHE INTERNAL "")
    set(ABSL_BUILD_MONOLITHIC_CPP_LIB OFF CACHE INTERNAL "")
    add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/third_party/abseil"
                     "${CMAKE_BINARY_DIR}/third_party/abseil")

    set(protobuf_INSTALL OFF CACHE INTERNAL "")
    set(protobuf_BUILD_TESTS OFF CACHE INTERNAL "")
    set(protobuf_BUILD_CONFORMANCE OFF CACHE INTERNAL "")
    set(protobuf_BUILD_EXAMPLES OFF CACHE INTERNAL "")
    set(protobuf_BUILD_LIBUPB OFF CACHE INTERNAL "")  # we build our own subset
    set(protobuf_DISABLE_RTTI ON CACHE INTERNAL "")
    set(protobuf_WITH_ZLIB OFF CACHE INTERNAL "")
    set(protobuf_BUILD_SHARED_LIBS OFF CACHE INTERNAL "")
    set(utf8_range_ENABLE_TESTS OFF CACHE INTERNAL "")
    set(utf8_range_ENABLE_INSTALL OFF CACHE INTERNAL "")
    add_subdirectory("${URPC_PROTOBUF_DIR}"
                     "${CMAKE_BINARY_DIR}/third_party/protobuf"
                     EXCLUDE_FROM_ALL)
    set(URPC_PROTOC_EXECUTABLE "$<TARGET_FILE:protoc>" CACHE STRING
        "protoc used for --upb_out generation (generator expression)")
    set(URPC_PROTOC_TARGET protoc)
    message(STATUS "urpc: system protoc unusable for --upb_out; building host protoc from third_party/protobuf")
  endif()
endif()

# ---------------------------------------------------------------------------
# GoogleTest / Google Benchmark (dev+test only; never in runtime artifacts)
# ---------------------------------------------------------------------------
if(BUILD_TESTING AND URPC_BUILD_TESTS AND NOT TARGET GTest::gtest)
  urpc_tp_require(googletest)
  set(INSTALL_GTEST OFF CACHE INTERNAL "")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/third_party/googletest"
                   "${CMAKE_BINARY_DIR}/third_party/googletest")
  if(NOT TARGET GTest::gtest)
    add_library(GTest::gtest ALIAS gtest)
  endif()
endif()

if(BUILD_TESTING AND URPC_BUILD_BENCH AND NOT TARGET benchmark::benchmark)
  urpc_tp_require(benchmark)
  set(BENCHMARK_ENABLE_TESTING OFF CACHE INTERNAL "")
  set(BENCHMARK_ENABLE_GTEST_TESTS OFF CACHE INTERNAL "")
  set(BENCHMARK_INSTALL_SHARE OFF CACHE INTERNAL "")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/third_party/benchmark"
                   "${CMAKE_BINARY_DIR}/third_party/benchmark")
  if(NOT TARGET benchmark::benchmark)
    add_library(benchmark::benchmark ALIAS benchmark)
  endif()
endif()
