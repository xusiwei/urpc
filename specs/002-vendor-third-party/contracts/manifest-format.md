# Contract: 依赖清单格式（third_party/versions.cmake）

清单是全部 C++ 三方依赖的单一事实源（FR-004），同时被获取命令
（tools/fetch_third_party.cmake）与构建（cmake/urpc-deps.cmake）
`include()`。语法为纯 CMake `set()`，无任何副作用语句。

## 变量命名

每依赖四个变量，`<NAME>` 为大写依赖名：

```cmake
set(URPC_TP_<NAME>_VERSION  "<tag>")     # 与来源 tag 完全一致
set(URPC_TP_<NAME>_URL     "<codeload 归档 URL>")
set(URPC_TP_<NAME>_SHA256  "<64 位小写十六进制>")
set(URPC_TP_<NAME>_LICENSE "<SPDX 标识符>")
```

依赖清单（固定六项，顺序即获取顺序）：

| <NAME> | 目录 | 说明 |
|--------|------|------|
| LIBUV | third_party/libuv | 运行时 |
| NGHTTP2 | third_party/nghttp2 | 运行时 |
| PROTOBUF | third_party/protobuf | 运行时（upb 子集）+ 宿主 protoc 源 |
| ABSEIL | third_party/abseil | protobuf/protoc 的传递构建依赖 |
| GOOGLETEST | third_party/googletest | 仅测试 |
| BENCHMARK | third_party/benchmark | 仅基准 |

## 不变量（消费方依赖的契约）

1. 文件只含 `set()` 与注释，无逻辑分支——include 安全幂等。
2. URL 必须由 VERSION 派生（同 tag 同内容）；SHA256 为该归档实测哈希。
3. ABSEIL 版本必须为 PROTOBUF 源内 cmake/dependencies.cmake 钦定版本。
4. 变更该文件是升级依赖的唯一合法路径（评审面即本文件 diff）。
5. 许可证字段必须与源码目录内实际 LICENSE 文件一致。

## 现行锚点（2026-09-10 实测）

见 [research.md §4](../research.md#4-完整性校验) 的 SHA256 表；
清单文件内容以仓库当前版本为准。
