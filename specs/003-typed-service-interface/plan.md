# Implementation Plan: 类 gRPC 的类型化服务接口（Typed Service Interface）

**Branch**: `003-typed-service-interface` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-typed-service-interface/spec.md`

## Summary

把 001 的"方法特质宏 + 字符串路径 + lambda 注册"API 升级为 gRPC C++ 风格的
类型化服务接口：以 protoc 插件（`--urpc_out`）从 .proto 生成三个生成物——
服务端纯虚接口类 `IXxxService`、客户端代理 `XxxServiceProxy`（继承同一
接口）、以及两端共用的桥接代码（编解码/方法表）。用户服务端继承接口类
重写方法、把实例整体注册到 `Server`；客户端从 `Channel` 构造代理直接调用
业务方法。客户端对象职责三分：Channel=连接、Client=控制面、Proxy=业务面。
内核（core）零改动，全部落在 libs/api 层与构建链上；存量 lambda 入口
兼容保留（FR-014）。

## Technical Context

**Language/Version**: C++17（宪法约束，禁用 C++20+ 特性）；生成器插件
本体 C++（与 vendored protobuf 同源同标准）

**Primary Dependencies**: 复用全部既有依赖——运行时 libuv/nghttp2/upb，
开发/测试 GoogleTest/Google Benchmark；生成器复用 vendored protoc 插件
体系（CodeGeneratorService 接口，随 protobuf_BUILD_LIBUPB=ON 已在构建
protoc-gen-upb/protoc-gen-upb_minitable，同一构建目标形态追加
protoc-gen-urpc）。**零新增依赖**（SC-005 / 原则 V）。

**Storage**: N/A（纯库 + 构建期生成物，无持久化）

**Testing**: GoogleTest 单元/集成（libs/api/test 扩展）；生成物正确性
由"编译即验证 + 金样对照"背书；端到端经迁移后的 examples-echo-e2e 与
全量 ctest；互操作保持 gRPC Python 对端套件全绿（FR-012）。

**Target Platform**: Linux、macOS、Windows 三平台 CI 全绿（宪法 III；
插件与生成物确定性执行，FR-008）

**Project Type**: library（C++ API 层扩展 + 构建链生成器插件）

**Performance Goals**: 接口层零拷贝直通（FR-007：直接使用 upb 生成类型，
无额外消息复制层）；基准沿用 001 基线门禁，本特性不得引入 >10% 中位退化
（接口层为模板内联 + 一次性方法表，理论开销为零）。

**Constraints**: 宪法 I–V；线协议行为完全不变（FR-012）；异常不穿越
边界（FR-013）；存量 API 兼容保留（FR-014）；unary-only（Assumptions）。

**Scale/Scope**: 单个 protoc 插件目标 + cmake 函数扩展 + api 层 ~4 个
新头/源文件 + 示例与测试迁移；生成物按 .proto 文件对产出。

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 | 门禁 | 结论 |
|------|------|------|
| I. gRPC 线协议兼容（不可妥协） | 线协议行为不变；官方对端互通全绿 | ✅ 本特性仅重塑用户侧 API；FR-012 显式冻结线行为；互操作套件继续为门禁（US4-3） |
| II. 分层内核与可绑定 API 边界 | 内核不依赖上层；边界无异常/STL 泄漏 | ✅ core 零改动；生成物与注册/代理机制全部在 libs/api；FR-013 异常终止于 api 层；生成物为 C++（阶段一语言），cabi 边界不受影响 |
| III. 跨平台构建纪律 | 三平台 CMake 全绿；平台代码收敛 | ✅ 插件为标准 protoc CodeGenerator，输出确定性文本；经既有 add_subdirectory(protobuf) 构建链三平台产出；无平台分支 |
| IV. 测试背书的变更（不可妥协） | 每行为变更由 GoogleTest/Benchmark 背书 | ✅ FR-001..014 对应 US 验收场景；生成器金样对照 + 编译期签名验证 + 端到端 + 互操作四层测试；基准回归门禁延续 |
| V. 依赖最小化且边界固定 | 依赖集合不变；不引入新依赖 | ✅ 插件复用 vendored protobuf 源内构建（与 protoc-gen-upb 同一机制，仅新增一个目标，不新增外部依赖项）；SC-005 可验证 |

## Project Structure

### Documentation (this feature)

```text
specs/003-typed-service-interface/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   └── service-interface.md   # 生成物公共形态 + 注册/代理/构造契约
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
third_party/protobuf/          # vendored（不改动）；构建链已有 protoc +
                               # upb 插件目标，新增 urpc 插件经 urpc-deps.cmake
                               # 选项接入（见下）
cmake/
├── urpc-deps.cmake            # 追加：protoc-gen-urpc 插件目标声明/
│                              #   挂载（protobuf_BUILD_LIBUPB 体系内）
└── urpc-proto.cmake           # 扩展：urpc_proto_upb() 增加 --urpc_out
                               #   产物（Xxx.service.h/.cc）与依赖接线
libs/api/
├── include/urpc/
│   ├── service.h              # （新增）生成接口的公共底座：方法描述符、
│   │                          #   接口注册辅助（RegisterService<IFoo>）
│   ├── proxy.h                # （新增）代理公共底座：ProxyBase（持有
│   │                          #   Channel*/Client*，执行远程调用的
│   │                          #   模板辅助）——生成代理继承它
│   ├── client.h               # 扩展：Channel/Client 职责三分整理
│   │                          #   （Channel=连接，Client=控制面）
│   └── unary.h                # 不变（存量入口，FR-014）
├── source/urpc_api_impl.cpp   # 扩展：RegisterService 桥接
└── test/
    ├── test_service_codegen.cpp   # （新增）生成物形态/编译期契约测试
    └── test_typed_e2e.cpp         # （新增）接口实现 + 代理 端到端
examples/echo/
├── echo.proto                 # 不变（同一描述驱动三件套生成）
├── echo_server_main.cpp       # 迁移：继承 IEchoService 实现 + 注册实例
├── echo_client_main.cpp       # 迁移：EchoServiceProxy 调用
└── CMakeLists.txt             # 接入 --urpc_out 产物
tools/                         # （可选金样）生成物快照留档目录
```

**Structure Decision**: 不新建顶层目录；生成器插件挂在 vendored protobuf
的插件构建体系上（与 protoc-gen-upb 并列的 protoc-gen-urpc 目标，源码
放置于 `third_party/` 之外——见 research.md §1 的放置决策），运行时底座
落在 `libs/api/include/urpc/{service.h,proxy.h}`。该结构与 001 的三层
目标（core/cabi/api）完全一致：本特性是 api 层 + 构建链的纵向扩展。

## Complexity Tracking

> 无宪法违规需要辩护；插件源码的物理放置（vendored protobuf 树外）在
> research.md §1 记录决策依据，不构成原则 V 违规（不新增外部依赖项，
> 复用同一构建体系）。

## Post-Design Constitution Re-Check（Phase 1 后复检）

| 原则 | Phase 1 设计事实 | 复检结论 |
|------|------------------|----------|
| I | 契约冻结线行为（FR-012）；代理 timeout 沿用既有 grpc-timeout 通道（research §6） | ✅ 无线协议触碰 |
| II | 全部新面落在 libs/api + 生成物（urpc::gen）；FR-013 异常终止于 api 层；core 零改动 | ✅ |
| III | 生成器为确定性文本输出；经既有 protobuf 枒件构建链三平台产出（research §1/§5，quickstart §5） | ✅ |
| IV | 四层验证（编译期 static_assert / 金样 / 行为 e2e / 互操作回归）+ 基准门禁延续（research §5） | ✅ |
| V | 零新增依赖项：protoc-gen-urpc 为仓库自有源码（generator/）经既有构建体系产出（research §1 放置决策） | ✅ |

**Gate 结论**：通过。进入 Phase 2（`$speckit-tasks`）无阻断项。
