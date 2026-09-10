# Implementation Plan: Unary Request/Response（一元请求/响应调用）

**Branch**: `001-unary-rpc` | **Date**: 2026-09-10 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-unary-rpc/spec.md`

## Summary

交付 urpc 框架的第一个纵向切片：明文直连环境下与 gRPC 线协议兼容的一元
调用（单请求 → 单响应）。基于 libuv 事件循环 + nghttp2 HTTP/2 + upb
protobuf 编解码，按既定三层目标（core / cabi / api）组织；提供服务端
方法注册、客户端异步+同步调用、截止时间与取消传播、并发多路复用、
优雅关闭、最小生命周期日志；验收以三层自动化验证（单元 / 基准留档 /
端到端示例）+ 官方 gRPC Python 对端互通为准。

## Technical Context

**Language/Version**: C++17（宪法约束，禁用 C++20+ 特性）

**Primary Dependencies**: libuv（≥1.46，异步 I/O）、nghttp2（≥1.62，
HTTP/2）、protobuf/upb（upb 运行时，随 protobuf 源发布，实现期固定最新
stable 版本号）；开发/测试依赖：GoogleTest（≥1.14）、Google Benchmark
（≥1.8）。全部经 CMake FetchContent 引入（优先 find_package 系统包，
缺失时自动拉取固定版本源码构建）。

**Storage**: N/A（纯库，无持久化）

**Testing**: GoogleTest（单元/集成）、Google Benchmark（性能基准，结果
留档）、gRPC Python（grpcio + grpcio-tools）编写互通对端脚本、
ctest 驱动全部三层验证。

**Target Platform**: Linux、macOS、Windows（宪法原则 III；CI 矩阵全覆盖）

**Project Type**: library（分层多目标 C++ 库 + 示例程序）

**Performance Goals**:（回环环境，1KiB 消息；详见 research.md §1）
- 单连接串行一元调用往返时延：p50 ≤ 300µs，p99 ≤ 1.5ms
- 单连接并发（4 在途）吞吐 ≥ 10,000 ops/s
- 回归门禁：对照留档基线，中位指标退化 > 10% 阻断合入

**Constraints**: 宪法原则 I–V（gRPC 线协议兼容不可妥协、分层内核 +
C-ABI 边界、跨平台、测试背书不可妥协、依赖集合固定）；明文直连，
无 TLS/压缩/流式/重试/服务发现。

**Scale/Scope**: 单连接 100 并发在途调用零错误（SC-005）；单条消息默认
上限 4MiB（可配置）。

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 | 门禁 | 结论 |
|------|------|------|
| I. gRPC 线协议兼容（不可妥协） | 线上语义与官方 gRPC 兼容；发布前过官方对端互通套件 | ✅ 本特性即以互通为验收（SC-004，gRPC Python 对端）；无私有协议扩展 |
| II. 分层内核与可绑定 API 边界 | core/cabi/api 三目标；边界无异常/STL 泄漏；阶段一仅 C++ | ✅ 源码结构即三层目标（见 Project Structure）；cabi 第一天存在；绑定目录仅占位 README |
| III. 跨平台构建纪律 | Linux/macOS/Windows 全绿；CMake 唯一入口；平台代码隔离 | ✅ CMake + presets；平台差异收敛于 core 平台抽象模块；CI 三平台矩阵（FR-010/SC-002） |
| IV. 测试背书的变更（不可妥协） | GoogleTest 单元 / Benchmark 基准 / 互通套件三线齐备 | ✅ test/ 与 bench/ 内嵌各模块；基准留档；gRPC Python 互通脚本 |
| V. 依赖最小化且边界固定 | 运行时依赖仅 libuv/nghttp2/upb；开发依赖仅 gtest/benchmark | ✅ 无新增依赖；日志为自研最小实现（不引第三方日志库）；测试依赖不进入运行时构件 |

## Project Structure

### Documentation (this feature)

```text
specs/001-unary-rpc/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── server-api.md
│   ├── client-api.md
│   ├── wire-protocol.md
│   └── logging.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
CMakeLists.txt              # 顶层：项目定义、选项、FetchContent 依赖
CMakePresets.json           # configure/build/test 标准预设
cmake/                      # CMake 工具模块（依赖封装、警告设定）
libs/
├── core/                   # 内核：事件循环封装、HTTP/2 会话、upb 编解码、路由
│   ├── include/urpc/core/  # 内核内部头（仅 core 目标可见）
│   ├── source/
│   ├── test/               # GoogleTest 单元测试
│   └── bench/              # Google Benchmark 基准
├── cabi/                   # C-ABI 边界层（稳定导出面，无异常/STL 泄漏）
│   ├── include/urpc/c/
│   ├── source/
│   └── test/
└── api/                    # C++17 公共 API（本特性主交付物）
    ├── include/urpc/
    ├── source/
    └── test/
interop/                    # gRPC Python 互通对端脚本 + 共享 proto
examples/                   # echo 服务端 + 客户端 quickstart 示例
bindings/                   # 阶段二占位（仅 README）
tools/                      # 辅助脚本（基准留档等）
docs/
```

**Structure Decision**: 采用会话中与用户定稿的三层多目标结构
（决策记录：FetchContent 依赖引入、libs/{core,cabi,api} 编译期强制分层、
测试与基准全部内嵌模块、include/source 命名对称）。跨模块的互通对端
放顶层 interop/，是内嵌原则的唯一例外（跨三层）。

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

无宪法违例，无需记录。
