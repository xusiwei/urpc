# Implementation Plan: 三方依赖源码化（third_party/ 统一组织）

**Branch**: `002-vendor-third-party` | **Date**: 2026-09-10 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-vendor-third-party/spec.md`

## Summary

将项目全部 C++ 三方依赖（libuv、nghttp2、protobuf、abseil、googletest、
benchmark）从「配置期 FetchContent 联网获取」改为「固定版本源码下载到
`third_party/`、构建只从本地目录消费」。交付三件套：单一版本清单
（`third_party/versions.cmake`）、跨平台幂等获取命令
（`cmake -P tools/fetch_third_party.cmake`，SHA256 校验）、重写后的
`cmake/urpc-deps.cmake`（配置期零网络、缺失依赖给出带指引的明确错误）。
Python 依赖维持 requirements 方式不变。

## Technical Context

**Language/Version**: CMake 脚本（≥3.21，script mode `-P`）+ 项目本体 C++17

**Primary Dependencies**: 与现清单一致的六个 C++ 依赖，版本与 SHA256
锚定：libuv 1.48.0、nghttp2 1.65.0、protobuf 30.2、abseil 20250127.0
（protobuf 钦定）、googletest 1.15.2、benchmark 1.9.1。全部来源为
codeload 归档 URL（本环境验证可达；release 资产 CDN 不可靠，不使用）。

**Storage**: `third_party/<name>/` 源码目录（工作产物，不入库）+
`.urpc-version` 标记文件（版本+哈希，幂等与一致性判据）

**Testing**: ctest 幂等冒烟（重复获取零变化）；缺失依赖→配置错误契约
用例；quickstart.md 手册演练（含断网构建）

**Target Platform**: Linux、macOS、Windows（cmake script mode 天然跨平台；
解压用 `file(ARCHIVE_EXTRACT)`，不依赖系统 tar/curl）

**Project Type**: build-infrastructure（库项目的依赖组织层）

**Performance Goals**: 获取命令在依赖已就位时 < 1s（纯标记比对）；
全新获取耗时受网络限制，失败可续（已就位依赖不重取）

**Constraints**: 宪法原则 V（不新增任何依赖；获取工具必须零第三方
依赖）；原则 III（三平台同一命令）；FR-009（构建图移除一切隐式下载）

**Scale/Scope**: 6 个依赖目录；清单单文件；获取脚本单文件

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 | 门禁 | 结论 |
|------|------|------|
| I. gRPC 线协议兼容 | 本特性不触碰线上语义与运行时代码 | ✅ 无影响 |
| II. 分层内核与可绑定 API 边界 | 仅改构建组织，目标分层不变 | ✅ 三层目标结构保持 |
| III. 跨平台构建纪律 | 获取命令与构建流程三平台一致（cmake script + file(ARCHIVE_EXTRACT)） | ✅ |
| IV. 测试背书的变更 | 幂等/缺失指引/清单升级三场景纳入 ctest 与 quickstart 演练 | ✅ |
| V. 依赖最小化且边界固定 | 依赖集合不变；获取工具零第三方依赖；vendoring 使「版本固定并经评审」从惯例变为机制（清单单文件评审） | ✅ 本特性是原则 V 的执法强化 |

## Project Structure

### Documentation (this feature)

```text
specs/002-vendor-third-party/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── manifest-format.md   # 清单文件格式契约
│   ├── fetch-command.md     # 获取命令行为契约
│   └── build-guard.md       # 构建期缺失依赖错误契约
└── tasks.md             # (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
third_party/
├── versions.cmake       # 依赖清单：单一事实源（入库）
├── README.md            # 目录说明与获取指引（入库）
├── <name>/              # 各依赖源码目录（gitignored，工作产物）
│   └── .urpc-version    # 版本+SHA256 标记（由获取命令写入）
tools/
└── fetch_third_party.cmake  # 幂等获取命令（入库，cmake -P 执行）
cmake/
└── urpc-deps.cmake      # 重写：仅从 third_party/ 消费；零网络；缺失即带指引报错
CMakePresets.json        # （不变）
```

**Structure Decision**: 沿用 001 定稿的仓库结构，新增 `third_party/`
（清单与 README 入库、源码目录忽略）与 `tools/fetch_third_party.cmake`；
`cmake/urpc-deps.cmake` 原地重写（对上层目标名 `uv_a`/
`nghttp2_static`/`urpc_upb`/`protoc`/`GTest::gtest`/
`benchmark::benchmark` 保持不变，上层 CMakeLists 零改动）。

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

无宪法违例，无需记录。
