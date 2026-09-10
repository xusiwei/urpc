# urpc-deps.cmake — single point of pinned third-party dependency versions.
#
# Policy (research.md #2, constitution Principle V):
#   * runtime deps: libuv / nghttp2 / upb (from protobuf source)
#   * dev/test deps: GoogleTest / Google Benchmark (never linked into runtime)
#   * system packages preferred when usable (find_package / find_program);
#     otherwise FetchContent pulls a pinned source tag.
#   * host protoc must support --upb_out (protobuf >= 23); a matching prebuilt
#     is downloaded automatically when the system one is missing or too old.

include(FetchContent)

set(URPC_DEP_LIBUV_VERSION     "1.48.0")
set(URPC_DEP_NGHTTP2_VERSION   "1.65.0")
set(URPC_DEP_PROTOBUF_VERSION  "30.2")
set(URPC_DEP_ABSEIL_VERSION    "20250127.0")  # pinned by protobuf v30.2
set(URPC_DEP_GTEST_VERSION     "1.15.2")
set(URPC_DEP_BENCHMARK_VERSION "1.9.1")

# ---------------------------------------------------------------------------
# libuv
# ---------------------------------------------------------------------------
find_package(libuv QUIET)
if(NOT TARGET libuv::libuv AND NOT TARGET uv_a AND NOT TARGET uv)
  FetchContent_Declare(libuv
    URL "https://github.com/libuv/libuv/archive/refs/tags/v${URPC_DEP_LIBUV_VERSION}.tar.gz" DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  set(LIBUV_BUILD_SHARED OFF CACHE INTERNAL "")
  FetchContent_MakeAvailable(libuv)
endif()
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
if(NOT TARGET nghttp2 AND NOT TARGET nghttp2_static)
  FetchContent_Declare(nghttp2
    URL "https://github.com/nghttp2/nghttp2/archive/refs/tags/v${URPC_DEP_NGHTTP2_VERSION}.tar.gz" DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  set(ENABLE_SHARED_LIB OFF CACHE INTERNAL "")
  set(ENABLE_STATIC_LIB ON  CACHE INTERNAL "")
  set(ENABLE_BIN         OFF CACHE INTERNAL "")
  set(ENABLE_EXAMPLES    OFF CACHE INTERNAL "")
  set(ENABLE_TESTS       OFF CACHE INTERNAL "")
  set(ENABLE_DOC         OFF CACHE INTERNAL "")
  set(ENABLE_HTTP3       OFF CACHE INTERNAL "")
  FetchContent_MakeAvailable(nghttp2)
endif()
if(TARGET nghttp2_static)
  set(URPC_NGHTTP2_TARGET nghttp2_static)
else()
  set(URPC_NGHTTP2_TARGET nghttp2)
endif()

# ---------------------------------------------------------------------------
# upb runtime (C subset of the protobuf source tree; no abseil, no libprotobuf)
# ---------------------------------------------------------------------------
if(NOT TARGET urpc_upb)
  FetchContent_Declare(protobuf_src
    URL "https://github.com/protocolbuffers/protobuf/archive/refs/tags/v${URPC_DEP_PROTOBUF_VERSION}.tar.gz" DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  FetchContent_GetProperties(protobuf_src)
  if(NOT protobuf_src_POPULATED)
    FetchContent_Populate(protobuf_src)
  endif()

  file(GLOB_RECURSE URPC_UPB_SOURCES
    "${protobuf_src_SOURCE_DIR}/upb/*.c")
  # drop tests/fuzzers/conformance/build-generated copies and reflection
  # (reflection needs generated descriptor tables which we do not use — typed
  # access comes from protoc --upb_out)
  list(FILTER URPC_UPB_SOURCES EXCLUDE REGEX "/(test|tests|fuzz|fuzzer|conformance|cmake|benchmark|benchmarks|reflection|json|text|util)/")
  list(FILTER URPC_UPB_SOURCES EXCLUDE REGEX "(_test|_tests|_fuzz|_fuzzer)\\.c$")
  list(FILTER URPC_UPB_SOURCES EXCLUDE REGEX "(^|/)test_[^/]*\\.c$")

  # utf8_range (upb's UTF-8 validation) — vendored in the protobuf tree
  list(APPEND URPC_UPB_SOURCES
    "${protobuf_src_SOURCE_DIR}/third_party/utf8_range/utf8_range.c")

  add_library(urpc_upb STATIC ${URPC_UPB_SOURCES})
  target_include_directories(urpc_upb PUBLIC
    "${protobuf_src_SOURCE_DIR}"
    "${protobuf_src_SOURCE_DIR}/third_party/utf8_range")
  target_compile_options(urpc_upb PRIVATE
    $<$<C_COMPILER_ID:GNU,Clang,AppleClang>:-Wno-declaration-after-statement>)
endif()

# ---------------------------------------------------------------------------
# host protoc with --upb_out support (protobuf >= 23)
# ---------------------------------------------------------------------------
function(_urpc_protoc_version PROTOC_BIN OUT_VAR)
  execute_process(COMMAND "${PROTOC_BIN}" --version
    OUTPUT_VARIABLE ver OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET RESULT_VARIABLE rc)
  if(NOT rc EQUAL 0)
    set(${OUT_VAR} 0 PARENT_SCOPE)
    return()
  endif()
  # "libprotoc 30.2" or "libprotoc 3.21.12"
  string(REGEX MATCH "[0-9]+\\.[0-9]+(\\.[0-9]+)?" num "${ver}")
  string(REGEX MATCH "^[0-9]+" major "${num}")
  set(${OUT_VAR} "${major}" PARENT_SCOPE)
endfunction()

function(_urpc_build_protoc_from_source)
  # Build the host protoc in-tree. protobuf's cmake reuses pre-existing
  # absl:: targets (see its cmake/abseil-cpp.cmake), so we provide abseil
  # ourselves from a pinned tarball.
  FetchContent_Declare(abseil_cpp
    URL "https://github.com/abseil/abseil-cpp/archive/refs/tags/${URPC_DEP_ABSEIL_VERSION}.tar.gz"
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  set(ABSL_ENABLE_TESTING OFF CACHE INTERNAL "")
  set(ABSL_PROPAGATE_CXX_STD ON CACHE INTERNAL "")
  set(ABSL_BUILD_MONOLITHIC_CPP_LIB OFF CACHE INTERNAL "")
  FetchContent_MakeAvailable(abseil_cpp)

  # protobuf_src is already populated by the upb section above
  set(protobuf_INSTALL OFF CACHE INTERNAL "")
  set(protobuf_BUILD_TESTS OFF CACHE INTERNAL "")
  set(protobuf_BUILD_CONFORMANCE OFF CACHE INTERNAL "")
  set(protobuf_BUILD_EXAMPLES OFF CACHE INTERNAL "")
  set(protobuf_BUILD_LIBUPB OFF CACHE INTERNAL "")  # we build our own upb subset
  set(protobuf_DISABLE_RTTI ON CACHE INTERNAL "")
  set(protobuf_WITH_ZLIB OFF CACHE INTERNAL "")
  set(protobuf_BUILD_SHARED_LIBS OFF CACHE INTERNAL "")
  set(utf8_range_ENABLE_TESTS OFF CACHE INTERNAL "")
  set(utf8_range_ENABLE_INSTALL OFF CACHE INTERNAL "")
  add_subdirectory("${protobuf_src_SOURCE_DIR}" "${protobuf_src_BINARY_DIR}"
                   EXCLUDE_FROM_ALL)
endfunction()

if(URPC_PROTOC_EXECUTABLE AND NOT EXISTS "${URPC_PROTOC_EXECUTABLE}")
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
    _urpc_build_protoc_from_source()
    set(URPC_PROTOC_EXECUTABLE "$<TARGET_FILE:protoc>" CACHE STRING
        "protoc used for --upb_out generation (generator expression)")
    set(URPC_PROTOC_TARGET protoc)
    message(STATUS "urpc: system protoc unusable for --upb_out; building host protoc from protobuf v${URPC_DEP_PROTOBUF_VERSION}")
  endif()
endif()

# ---------------------------------------------------------------------------
# GoogleTest / Google Benchmark (dev+test only)
# ---------------------------------------------------------------------------
if(BUILD_TESTING AND URPC_BUILD_TESTS AND NOT TARGET GTest::gtest)
  FetchContent_Declare(googletest
    URL "https://github.com/google/googletest/archive/refs/tags/v${URPC_DEP_GTEST_VERSION}.tar.gz" DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  set(INSTALL_GTEST OFF CACHE INTERNAL "")
  FetchContent_MakeAvailable(googletest)
  if(NOT TARGET GTest::gtest)
    add_library(GTest::gtest ALIAS gtest)
  endif()
endif()

if(BUILD_TESTING AND URPC_BUILD_BENCH AND NOT TARGET benchmark::benchmark)
  FetchContent_Declare(benchmark
    URL "https://github.com/google/benchmark/archive/refs/tags/v${URPC_DEP_BENCHMARK_VERSION}.tar.gz" DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  set(BENCHMARK_ENABLE_TESTING OFF CACHE INTERNAL "")
  set(BENCHMARK_ENABLE_GTEST_TESTS OFF CACHE INTERNAL "")
  set(BENCHMARK_INSTALL_SHARE OFF CACHE INTERNAL "")
  FetchContent_MakeAvailable(benchmark)
  if(NOT TARGET benchmark::benchmark)
    add_library(benchmark::benchmark ALIAS benchmark)
  endif()
endif()
