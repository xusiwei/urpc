---
description: "Task list for unary request/response feature implementation"
---

# Tasks: Unary Request/Response（一元请求/响应调用）

**Input**: Design documents from `/specs/001-unary-rpc/`

**Prerequisites**: plan.md (required), spec.md (required), research.md,
data-model.md, contracts/（server-api / client-api / wire-protocol / logging）

**Tests**: 测试任务已包含——规格 FR-009 与宪法原则 IV 明确要求三层自动化
验证（单元 / 性能基准 / 端到端 + 互通）。

**Organization**: 按用户故事（US1–US7，优先级 P1→P3）分阶段组织；每阶段
可独立实现、独立验证。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 所属用户故事（US1–US7）
- 每条任务含确切文件路径

## Path Conventions

采用 plan.md 定稿结构：`libs/{core,cabi,api}/`（各含 `include/`、
`source/`、`test/`，core 另含 `bench/`）、`interop/`、`examples/`、
`tools/`、`cmake/`。

---

## Phase 1: Setup（共享基础设施）

**Purpose**: 工程骨架与依赖引入

- [x] T001 创建顶层构建骨架：`CMakeLists.txt`（项目定义、选项
      `URPC_BUILD_TESTS/URPC_BUILD_BENCH/URPC_BUILD_EXAMPLES`、
      `URPC_WERROR`）、`CMakePresets.json`（debug/release ×
      Linux/macOS/Windows 预设，及 verify/bench/interop 测试预设）
- [x] T002 [P] 创建依赖封装 `cmake/urpc-deps.cmake`：find_package 优先、
      缺失时 FetchContent 固定 tag 引入 libuv(≥1.46)/nghttp2(≥1.62)/
      protobuf(upb)/GoogleTest(≥1.14)/benchmark(≥1.8)，版本单点声明
- [x] T003 [P] 创建目录骨架与占位：`libs/core`、`libs/cabi`、`libs/api`
      （各含 `include/`、`source/`、`test/`，core 含 `bench/`）、
      `interop/python/`、`examples/echo/`、`tools/`、`bindings/README.md`
      （阶段二占位说明）、`docs/`

---

## Phase 2: Foundational（阻塞性前置，全部故事依赖）

**Purpose**: 内核公共设施；未完成前不得开始任何用户故事

- [ ] T004 实现 `libs/core` LoopRunner：libuv 专属循环线程、
      `uv_async_t` 闭包投递入口、优雅停机（`source/urpc_loop.cpp`，
      头 `include/urpc/core/loop.h`）
- [ ] T005 [P] 实现 `libs/core` Status/StatusCode（FR-003 闭合集合 +
      消息）与 Result 形态（`include/urpc/core/status.h`）
- [ ] T006 [P] 实现最小结构化日志：级别/类别/闭合事件集合/可注入 sink
      （`libs/core/source/urpc_log.cpp`、`include/urpc/core/log.h`，
      契约见 `specs/001-unary-rpc/contracts/logging.md`）
- [ ] T007 [P] 实现平台抽象模块：TCP listen/connect 封装 uv_tcp、
      平台差异（socket 选项、错误码映射）收敛于
      `libs/core/source/platform/`（原则 III）
- [ ] T008 实现 nghttp2 会话封装：服务端/客户端会话工厂、回调桥
      （on_header/on_data/on_stream_close/on_frame_send），帧收发缓冲
      （`libs/core/source/urpc_h2_session.cpp`）
- [ ] T009 [P] 实现 upb 消息编解码助手：5 字节前缀帧、编码/解码、
      接收缓冲上限（默认 4MiB 可配）（`libs/core/source/urpc_codec.cpp`）
- [ ] T010 [P] 实现 proto→upb 代码生成 CMake 宏（protoc --upb_out 源内
      protobuf）与示例用 `examples/echo/echo.proto` 接线
      （`cmake/urpc-proto.cmake`）
- [ ] T011 实现 Router：`/服务名/方法名` → handler 只读快照表、动态
      注册、重复路径拒绝（`libs/core/source/urpc_router.cpp`）
- [ ] T012 实现 cabi 边界骨架：Status/handle/错误码 C 面（无异常/STL
      泄漏，`libs/cabi/include/urpc/c/`、`source/`）（原则 II）
- [ ] T013 单元测试（GoogleTest）：T004–T012 对应
      `libs/core/test/test_loop.cpp`、`test_status.cpp`、`test_log.cpp`、
      `test_h2_session.cpp`（预置帧序列）、`test_codec.cpp`（含零长度/
      超限）、`test_router.cpp`（含重复注册拒绝）、`libs/cabi/test/
      test_cabi_surface.cpp`；接入 `ctest --preset verify`

**Checkpoint**: 基础设施就绪，各用户故事可并行开始

---

## Phase 3: User Story 1 - 服务端发布一元方法 (Priority: P1) 🎯 MVP

**Goal**: 注册一元方法并在地址上提供服务：请求→处理器→响应/状态

**Independent Test**: 启动仅含 Echo 方法的服务端，以核心级客户端会话
发起调用，断言收到处理器返回的响应（spec US1 场景 1/2）

### Tests for User Story 1

- [ ] T014 [P] [US1] 集成测试先行：服务端路由→处理器→响应闭环 +
      动态注册 + 空消息（`libs/core/test/test_server_unary.cpp`，用
      nghttp2 客户端会话作对端，先失败后实现）

### Implementation for User Story 1

- [ ] T015 [US1] 服务端连接管理：accept、每连接 h2 服务会话、连接
      生命周期日志（`libs/core/source/urpc_server_conn.cpp`）
- [ ] T016 [US1] 一元请求解析与分发：headers 校验（:method/:path/
      content-type/te）、单消息组帧、END_STREAM → 派发 Router
      （`libs/core/source/urpc_server_unary.cpp`，线语义见
      contracts/wire-protocol.md）
- [ ] T017 [US1] 响应路径：`:status 200` + DATA（5 字节前缀）+
      trailers（grpc-status/grpc-message 百分号编码）；错误仅 trailers
      终结（`libs/core/source/urpc_server_unary.cpp`）
- [ ] T018 [US1] ServerContext：截止时间视图、取消回调注册、
      TimeRemaining（`libs/core/source/urpc_server_context.cpp`）
- [ ] T019 [US1] api 层 Server：ServerBuilder/BuildAndStart/RegisterUnary
      （upb 强类型模板桥）/基础 Stop（完整优雅排空在 US4）
      （`libs/api/source/server.cpp`、`include/urpc/server.h`，契约见
      contracts/server-api.md）
- [ ] T020 [US1] api 层测试：注册 API 语义（重复注册错误、动态注册、
      默认 4MiB 上限配置）（`libs/api/test/test_server_api.cpp`）

**Checkpoint**: US1 独立可验证（核心级对端）

---

## Phase 4: User Story 2 - 客户端发起一元调用 (Priority: P1) 🎯 MVP

**Goal**: 指定地址+方法发起一元调用，异步/同步获得响应或状态

**Independent Test**: urpc 客户端调用 US1 服务端成功；未知方法得
UNIMPLEMENTED（spec US2 场景 1/2）

### Tests for User Story 2

- [ ] T021 [P] [US2] 集成测试先行：进程内 urpc 客户端 ↔ urpc 服务端
      回环（成功 + UNIMPLEMENTED + 空消息）（`libs/api/test/
      test_client_server_loop.cpp`，先失败后实现）

### Implementation for User Story 2

- [ ] T022 [US2] 客户端通道：连接建立（懒连接）、h2 客户端会话、
      调用发起（HEADERS + 单 DATA + END_STREAM、grpc-timeout 编码）
      （`libs/core/source/urpc_channel.cpp`）
- [ ] T023 [US2] 响应终结：headers/DATA/trailers 解析 → Result、
      流↔调用配对、终态恰好一次投递、通道断开 → UNAVAILABLE
      （`libs/core/source/urpc_call.cpp`）
- [ ] T024 [US2] 同步/异步入口：线程安全投递至 LoopRunner、等待原语、
      事件循环线程误用快速失败检测（`libs/core/source/urpc_sync.cpp`）
- [ ] T025 [US2] api 层 Channel/Stub：CallAsync（回调恰好一次）/
      Call（同步便捷）/ Cancel/代理对象线程安全
      （`libs/api/source/client.cpp`、`include/urpc/client.h`，契约见
      contracts/client-api.md）
- [ ] T026 [US2] api 层测试：同步接口线程规则（循环线程内调用返回
      明确错误）、Cancel、UNAVAILABLE（`libs/api/test/test_client_api.cpp`）

**Checkpoint**: US1+US2 构成最小闭环

---

## Phase 5: User Story 3 - 端到端示例程序 (Priority: P1) 🎯 MVP

**Goal**: 开箱即用的 echo 示例（服务端+客户端进程），回环完成完整调用

**Independent Test**: 三平台构建并运行示例，退出码 0（spec US3 场景 1/2）

### Implementation for User Story 3

- [ ] T027 [US3] 示例服务端进程：注册 Echo、启动/日志、优雅退出码
      （`examples/echo/echo_server_main.cpp`）
- [ ] T028 [P] [US3] 示例客户端进程：循环调用并校验回显、成功摘要、
      退出码语义（`examples/echo/echo_client_main.cpp`）
- [ ] T029 [US3] ctest 端到端：以超时保护拉起服务端+客户端子进程、
      断言退出码 0（`examples/echo/CMakeLists.txt` 接入 verify 预设）
- [ ] T030 [US3] 对照 `specs/001-unary-rpc/quickstart.md` §1–§2 演练
      通过（含日志事件可见性检查）

**Checkpoint**: MVP（P1 三故事）完成，可演示

---

## Phase 6: User Story 4 - 错误与截止时间语义 (Priority: P2)

**Goal**: 超时/未知方法/处理失败/超限的全套状态语义 + 取消传播 +
优雅关闭

**Independent Test**: 构造超时、未知方法、处理器失败、超大消息、
关闭排空五类场景，逐一断言状态码（spec US4 场景 1–3 + FR-012）

### Tests for User Story 4

- [ ] T031 [P] [US4] 测试先行：超时→DEADLINE_EXCEEDED 且处理器收取消
      通知；处理器失败→INTERNAL 且服务端存活；超限→
      RESOURCE_EXHAUSTED；解码失败→DATA_LOSS 连接保持
      （`libs/api/test/test_error_semantics.cpp`）

### Implementation for User Story 4

- [ ] T032 [US4] 截止时间执行：双端 libuv 定时器、grpc-timeout 编解码、
      服务端取消传播至 ServerContext 回调、迟到 done 拒绝
      （`libs/core/source/urpc_deadline.cpp`）
- [ ] T033 [US4] 客户端本地取消：Cancel → RST_STREAM/CANCEL、服务端
      处理器取消回调、资源不悬挂（`libs/core/source/urpc_call.cpp` 扩展）
- [ ] T034 [US4] 优雅关闭：Shutdown(grace) → GOAWAY（最后可接受流）→
      排空等待/宽限 → 强制取消（UNAVAILABLE）→ 资源释放
      （`libs/core/source/urpc_server.cpp` 扩展，FR-012）
- [ ] T035 [US4] 关闭语义测试：宽限期内完成正常返回、宽限期后
      UNAVAILABLE、状态机 STARTING→RUNNING→DRAINING→STOPPED
      （`libs/api/test/test_shutdown.cpp`）

**Checkpoint**: 错误语义完整

---

## Phase 7: User Story 5 - 与官方 gRPC 对端互通 (Priority: P2)

**Goal**: 官方 gRPC Python 客户端调 urpc 服务端、urpc 客户端调官方
服务端，成功与错误场景互通

**Independent Test**: `ctest --preset interop` 四象限全绿
（spec US5 场景 1/2，SC-004）

### Implementation for User Story 5

- [ ] T036 [P] [US5] Python 对端脚本：requirements.txt（grpcio 固定版
      本）、共享 proto、peer_client.py / peer_server.py（成功 +
      UNIMPLEMENTED + DEADLINE_EXCEEDED 场景）（`interop/python/`）
- [ ] T037 [US5] ctest interop 接线：四象限（官方客户端×urpc 服务端 /
      urpc 客户端×官方服务端），Python 缺失时显式 SKIP 并提示
      （`interop/CMakeLists.txt`）
- [ ] T038 [US5] 线协议合规修正：以互通结果驱动——content-type 变体
      容忍、grpc-message 百分号编码、HTTP/2 SETTINGS/GOAWAY/PING 行为、
      错误 trailers 提前终结（`libs/core/source/` 相应文件，对照
      contracts/wire-protocol.md 逐项核对）

**Checkpoint**: 原则 I 门禁在特性内闭环

---

## Phase 8: User Story 6 - 并发一元调用 (Priority: P3)

**Goal**: 单连接 HTTP/2 多路流并发、代理对象线程安全、服务端并行处理

**Independent Test**: 2 线程共用同一 stub、单连接 100 在途调用全部
零错误配对、总耗时接近并行（spec US6，SC-005）

### Tests for User Story 6

- [ ] T039 [US6] 测试先行：100 在途并发配对 + 双线程共用代理对象 +
      延迟服务端下的并行度断言（`libs/api/test/test_concurrency.cpp`）

### Implementation for User Story 6

- [ ] T040 [US6] 并发硬化：流表锁策略、逐流接收缓冲隔离、nghttp2
      默认流控下的多路复用、连接写聚合适度性（`libs/core/source/
      urpc_channel.cpp`、`urpc_server_conn.cpp` 扩展）
- [ ] T041 [US6] 资源泄漏检查：并发压测下句柄/内存稳定（uv_handle
      计数、ASan/Valgrind 任一纳入 verify 预设可选项）
      （`libs/core/test/test_leak_stress.cpp`）

**Checkpoint**: 并发能力达标

---

## Phase 9: User Story 7 - 性能基线建立 (Priority: P3)

**Goal**: 可重复基准（串行 RTT / 并发吞吐）、结果 JSON 留档、
回归对比门禁

**Independent Test**: 连续多轮运行波动 ≤10% 且每轮留档；对照基线
退化 >10% 时门禁失败（spec US7，SC-003，research.md §1）

### Implementation for User Story 7

- [ ] T042 [US7] 基准用例：串行一元 RTT（p50/p99）与 4 在途吞吐
      （1KiB 回环）（`libs/core/bench/bench_unary.cpp`，Google
      Benchmark）
- [ ] T043 [US7] 留档与门禁：结果导出 JSON 至 `tools/baselines/`、
      对比脚本（中位退化 >10% 退出非零）、接入 `ctest --preset bench`
      （`tools/compare_baseline.py`、`tools/` 约定）
- [ ] T044 [US7] 基线首录：三平台各录首份基线并入库，记录环境说明
      （`tools/baselines/README.md`）

**Checkpoint**: 性能可回归守护

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: 跨故事收尾

- [ ] T045 [P] 代码规范：clang-format/clang-tidy 配置 + CI 工作流
      （三平台矩阵：构建 + verify + bench + 可选 interop，宪法原则
      III/IV）（`.github/workflows/ci.yml` 或 `tools/ci/`）
- [ ] T046 [P] 文档：`docs/architecture.md`（目录结构与分层决策）、
      `README.md`（构建/使用/示例指引，链接 quickstart.md）
- [ ] T047 全量走查 `specs/001-unary-rpc/quickstart.md` §1–§5（含
      30 分钟上手复刻，SC-001/SC-002）
- [ ] T048 三平台验证收口：Windows/MSVC 与 macOS/Clang 全套 verify
      通过、平台代码未散布（原则 III 终检）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1–2**: Setup → Foundational（阻塞所有故事）
- **Phase 3+**: 各故事依赖 Foundational 完成；可并行（有人力时）或按
  P1→P2→P3 顺序执行
- **Phase 10**: 依赖全部所需故事完成

### User Story Dependencies

- **US1 (P1)**: Foundational 后即可开始，无故事间依赖
- **US2 (P1)**: 实现不依赖 US1；回环集成测试需 US1 服务端（先核心级
  会话自测，再联测）
- **US3 (P1)**: 依赖 US1+US2（示例即二者组装）
- **US4 (P2)**: 依赖 US1/US2 的基础闭环（语义叠加）
- **US5 (P2)**: 依赖 US1（服务端被调）+ US2（调用官方端）
- **US6 (P3)**: 依赖 US2 通道与流表（并发硬化）
- **US7 (P3)**: 依赖 US2（基准对象）；与 US5/US6 可并行

### Within Each User Story

- 测试先行（先失败后实现，宪法原则 IV）
- 数据/实体 → 内核机制 → api 层 → 集成/联测
- 故事内 Checkpoint 通过后再进入下一优先级

### Parallel Opportunities

- Phase 1: T002、T003 并行（T001 先行）
- Phase 2: T005–T007、T009–T010 相互并行（T004、T008 先行）
- Phase 3–9: 各故事间可并行（不同模块目录）；故事内 [P] 标记任务并行
- 示例：US5 的 Python 脚本（T036）可与 US4 实现并行

---

## Parallel Example: User Story 2

```bash
# 测试与核心实现并行启动（不同文件）：
Task: "T021 [P] [US2] 集成测试先行 libs/api/test/test_client_server_loop.cpp"
Task: "T022 [US2] 客户端通道 libs/core/source/urpc_channel.cpp"

# 通道与响应终结完成后：
Task: "T024 [US2] 同步/异步入口 libs/core/source/urpc_sync.cpp"
Task: "T025 [US2] api 层 Channel/Stub libs/api/source/client.cpp"
```

---

## Implementation Strategy

### MVP First（P1 三故事 = 最小可演示闭环）

1. 完成 Phase 1: Setup
2. 完成 Phase 2: Foundational（阻塞一切，先筑牢）
3. 完成 Phase 3: US1 → 独立验证
4. 完成 Phase 4: US2 → 与 US1 联测闭环
5. 完成 Phase 5: US3 → **STOP and VALIDATE**：运行示例 + quickstart
   §1–§2，MVP 可演示

### Incremental Delivery

1. Setup + Foundational → 基础就绪
2. +US1/US2/US3 → MVP（演示/试用）
3. +US4 → 生产语义完整（超时/取消/优雅关闭）
4. +US5 → gRPC 生态互通（发布门禁就位）
5. +US6/US7 → 并发与性能守护
6. Polish → 全量走查 + 三平台收口

### Parallel Team Strategy

1. 团队共筑 Setup + Foundational
2. 之后可分流：A→US4，B→US5，C→US6/US7（互不冲突的模块面）
3. 各故事独立集成、独立验收

---

## Notes

- [P] = 不同文件且无未完成依赖
- [Story] 标签映射 spec.md 用户故事，便于追溯
- 每故事独立可完成、可验证；测试先行并确认失败后再实现
- 每任务或逻辑组完成后提交；Checkpoint 处停下独立验证
- 避免：含糊任务、同文件冲突、破坏独立性的跨故事依赖
