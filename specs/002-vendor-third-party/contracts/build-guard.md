# Contract: 构建期依赖门卫（cmake/urpc-deps.cmake）

## 离线不变量

配置期代码路径不存在任何下载原语（无 `FetchContent`、无
`file(DOWNLOAD)`）。依赖就位时断网配置+构建必须成功——离线性是
结构性保证（FR-003/FR-009），不是运行时开关。

## 就位判据

对清单中每个依赖：`third_party/<name>/.urpc-version` 存在，且其
version/sha256 与 `third_party/versions.cmake` 一致。
标记与目录内容不匹配（半成品、手工解压、清单升级后未重取）一律视为
未就位。

## 缺失时错误契约

任一依赖未就位 → 配置立即失败（FATAL_ERROR，非警告），消息必须包含：

1. 未就位依赖名（与清单版本对照）；
2. 修复指引原文：`cmake -P tools/fetch_third_party.cmake`；
3. 提示该命令需在仓库根执行且需要网络。

模板：

```text
urpc: third-party dependency '<name>' (version <v>) is not vendored.
      Run:  cmake -P tools/fetch_third_party.cmake
      (from the repository root; requires network access)
```

## 消费契约

就位后构建从本地目录消费，且对上层暴露的目标名保持稳定
（libs/* 的 CMakeLists 零改动）：

| 本地来源 | 上层可见目标 |
|----------|--------------|
| third_party/libuv | `uv_a`（经 `URPC_LIBUV_TARGET`） |
| third_party/nghttp2 | `nghttp2_static`（经 `URPC_NGHTTP2_TARGET`） |
| third_party/protobuf | `urpc_upb`（upb C 子集 + vendored utf8_range）与宿主 `protoc`（+ third_party/abseil） |
| third_party/googletest | `GTest::gtest`（仅 BUILD_TESTING 且 URPC_BUILD_TESTS） |
| third_party/benchmark | `benchmark::benchmark`（仅 BUILD_TESTING 且 URPC_BUILD_BENCH） |

测试/基准目标不得链接进任何运行时构件（宪法 V 延续）。
