# third_party/versions.cmake — single source of truth for vendored C++
# dependencies (spec 002-vendor-third-party).
#
# Contract: specs/002-vendor-third-party/contracts/manifest-format.md
#  - this file contains ONLY set() calls and comments (include-safe)
#  - URL is derived from the tag; SHA256 anchors the exact archive
#  - changing this file is the ONLY sanctioned way to upgrade a dependency
#  - ABSEIL must stay pinned to the version protobuf's cmake expects

set(URPC_TP_LIBUV_VERSION  "1.48.0")
set(URPC_TP_LIBUV_URL      "https://github.com/libuv/libuv/archive/refs/tags/v1.48.0.tar.gz")
set(URPC_TP_LIBUV_SHA256   "8c253adb0f800926a6cbd1c6576abae0bc8eb86a4f891049b72f9e5b7dc58f33")
set(URPC_TP_LIBUV_LICENSE  "MIT")

set(URPC_TP_NGHTTP2_VERSION "1.65.0")
set(URPC_TP_NGHTTP2_URL     "https://github.com/nghttp2/nghttp2/archive/refs/tags/v1.65.0.tar.gz")
set(URPC_TP_NGHTTP2_SHA256  "bcf08112bd583f8543776d086dcdede159b87e1261a36e6ae1d931c812a3ca70")
set(URPC_TP_NGHTTP2_LICENSE "MIT")

set(URPC_TP_PROTOBUF_VERSION "30.2")
set(URPC_TP_PROTOBUF_URL     "https://github.com/protocolbuffers/protobuf/archive/refs/tags/v30.2.tar.gz")
set(URPC_TP_PROTOBUF_SHA256  "07a43d88fe5a38e434c7f94129cad56a4c43a51f99336074d0799c2f7d4e44c5")
set(URPC_TP_PROTOBUF_LICENSE "BSD-3-Clause")

set(URPC_TP_ABSEIL_VERSION "20250127.0")
set(URPC_TP_ABSEIL_URL     "https://github.com/abseil/abseil-cpp/archive/refs/tags/20250127.0.tar.gz")
set(URPC_TP_ABSEIL_SHA256  "16242f394245627e508ec6bb296b433c90f8d914f73b9c026fddb905e27276e8")
set(URPC_TP_ABSEIL_LICENSE "Apache-2.0")

set(URPC_TP_GOOGLETEST_VERSION "1.15.2")
set(URPC_TP_GOOGLETEST_URL     "https://github.com/google/googletest/archive/refs/tags/v1.15.2.tar.gz")
set(URPC_TP_GOOGLETEST_SHA256  "7b42b4d6ed48810c5362c265a17faebe90dc2373c885e5216439d37927f02926")
set(URPC_TP_GOOGLETEST_LICENSE "BSD-3-Clause")

set(URPC_TP_BENCHMARK_VERSION "1.9.1")
set(URPC_TP_BENCHMARK_URL     "https://github.com/google/benchmark/archive/refs/tags/v1.9.1.tar.gz")
set(URPC_TP_BENCHMARK_SHA256  "32131c08ee31eeff2c8968d7e874f3cb648034377dfc32a4c377fa8796d84981")
set(URPC_TP_BENCHMARK_LICENSE "Apache-2.0")
