---
description: "Task list for third-party vendoring feature implementation"
---

# Tasks: 三方依赖源码化（third_party/ 统一组织）

**Input**: Design documents from `/specs/002-vendor-third-party/`

**Prerequisites**: plan.md (required), spec.md (required), research.md,
data-model.md, contracts/（manifest-format / fetch-command / build-guard）

**Tests**: 测试任务已包含——规格 FR-002/006/007 与成功标准 SC-003 明确
要求幂等、门卫错误契约与目录集合断言可自动化验证。

**Organization**: 按用户故事（US1–US4，优先级 P1→P2）分阶段组织；
每阶段可独立实现、独立验证。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 所属用户故事（US1–US4）
- 每条任务含确切文件路径

## Path Conventions

采用 plan.md 定稿结构：`third_party/`（versions.cmake + README.md 入库，
源码目录 gitignored）、`tools/fetch_third_party.cmake`、
`cmake/urpc-deps.cmake`。

---

## Phase 1: Setup（共享基础设施）

**Purpose**: 清单与目录策略就位

- [x] T001 创建依赖清单 `third_party/versions.cmake`：六依赖
      （libuv/nghttp2/protobuf/abseil/googletest/benchmark）的
      VERSION/URL/SHA256/LICENSE 四变量组，哈希取
      `specs/002-vendor-third-party/research.md` §4 实测锚点，
      语法遵守 `contracts/manifest-format.md`（仅 set() 与注释）
- [x] T002 [P] 调整 `.gitignore`（忽略 `third_party/*`，反向保留
      `!third_party/versions.cmake` 与 `!third_party/README.md`）并创建
      `third_party/README.md`（目录用途、获取命令、升级路径说明）

---

## Phase 2: User Story 1 - 一条命令获取全部依赖源码 (Priority: P1) 🎯 MVP

**Goal**: `cmake -P tools/fetch_third_party.cmake` 幂等拉取六依赖源码到
`third_party/<name>/`（SHA256 校验 + 标记文件）

**Independent Test**: 删除 third_party/ 后执行命令断言 fetched=6；重复
执行断言 fetched=0 skipped=6 且文件树零变化（spec US1 场景 1/2/3）

### Implementation for User Story 1

- [x] T003 [US1] 实现获取命令 `tools/fetch_third_party.cmake`：include
      清单、逐依赖标记比对（MATCHED 跳过 / MISMATCH 清目录重取 /
      MISSING 获取）、下载（file(DOWNLOAD)，系统 curl 回退）、SHA256
      校验、解压剥离归档顶层目录、写 `.urpc-version` 标记、逐依赖状态
      行输出、汇总 fetched/skipped 与退出码；行为契约见
      `contracts/fetch-command.md`
- [x] T004 [US1] 幂等冒烟接入：脚本支持 `-DURPC_TP_CHECK_ONLY=ON`
      仅校验模式（只做标记比对，零网络），顶层 `CMakeLists.txt` 注册
      ctest `vendor-third-party-idempotent`（LABELS vendor，断言六依赖
      全部 MATCHED）；按 quickstart §1 验证两轮真实执行行为

**Checkpoint**: US1 独立可验证（获取 → 幂等重取）

---

## Phase 3: User Story 2 - 构建只从 third_party/ 消费 (Priority: P1) 🎯 MVP

**Goal**: 配置期零网络、缺失依赖带指引失败、全量构建从本地源码消费

**Independent Test**: 断网环境全量配置+构建成功；删任一依赖目录后配置
失败且错误含获取命令（spec US2 场景 1/2）

### Implementation for User Story 2

- [x] T005 [US2] 重写 `cmake/urpc-deps.cmake`：删除全部
      FetchContent/find_package 优先路径；逐依赖门卫校验
      `.urpc-version`（不符即 FATAL_ERROR，消息模板见
      `contracts/build-guard.md`）；`add_subdirectory(third_party/...)`
      消费 libuv/nghttp2/googletest/benchmark/abseil/protobuf；
      `urpc_upb` 子集与宿主 protoc 构建逻辑平移到
      third_party/protobuf（排除规则与选项不变）；上层目标名映射
      保持（uv_a/nghttp2_static/urpc_upb/protoc/GTest::gtest/
      benchmark::benchmark），libs/* 的 CMakeLists 零改动
- [x] T006 [US2] 门卫契约用例 `tools/test/build_guard.cmake` + ctest
      接入（LABELS vendor）：临时挪走 `third_party/libuv` → 执行
      `cmake -S . -B <tmp>` 断言配置失败且输出含
      `cmake -P tools/fetch_third_party.cmake` 字样 → 还原目录
- [x] T007 [US2] 全量验证：全新 build 目录（删除旧 build/）配置+构建+
      ctest 全绿；检查配置日志零下载行为；按 quickstart §2 演练断网
      场景

**Checkpoint**: US1+US2 构成 MVP（源码化闭环）

---

## Phase 4: User Story 3 - 清单单文件升级 (Priority: P2)

**Goal**: 版本只存在于清单一处；升级路径单文件生效

**Independent Test**: grep 全仓库依赖版本字面量仅命中
third_party/versions.cmake；quickstart §4 升级演练通过
（spec US3 场景 1/2）

### Implementation for User Story 3

- [x] T008 [US3] 单源守护用例 `tools/test/single_source.cmake` +
      ctest 接入（LABELS vendor）：扫描 `cmake/`、`CMakeLists.txt`、
      `CMakePresets.json`、`libs/`、`tools/` 不得出现依赖版本号
      字面量（唯一例外清单文件自身）；走查 quickstart §4 升级演练
      并记录结果

**Checkpoint**: 升级面收敛到单文件

---

## Phase 5: User Story 4 - Python 依赖豁免 (Priority: P2)

**Goal**: third_party/ 仅含清单声明的 C++ 依赖，无 Python 产物

**Independent Test**: 目录集合断言通过（spec US4 场景 1）

### Implementation for User Story 4

- [x] T009 [US4] 目录集合断言 `tools/test/directory_set.cmake` +
      ctest 接入（LABELS vendor）：third_party/ 顶层恰为六依赖目录 +
      versions.cmake + README.md（+ tools/test 白名单），无
      site-packages/egg/wheel 等 Python 痕迹

**Checkpoint**: 边界明确

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 跨故事收尾与文档同步

- [x] T010 [P] 文档同步：根 `README.md` 构建指引增加获取命令步骤；
        `specs/001-unary-rpc/research.md` §2 顶部加 superseded 标注
        （指向 specs/002-vendor-third-party/）
- [x] T011 全量走查 `specs/002-vendor-third-party/quickstart.md`
        §1–§5（含幂等、断网、缺失指引、升级演练、Python 豁免）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1**: 无依赖，立即可开始
- **Phase 2 (US1)**: 依赖 T001（清单）
- **Phase 3 (US2)**: 依赖 US1（依赖须先就位才能消费）
- **Phase 4/5 (US3/US4)**: 依赖 US1；可与 US2 并行（不同文件面）
- **Phase 6**: 依赖全部故事完成

### User Story Dependencies

- **US1 (P1)**: T001 后即可开始
- **US2 (P1)**: 需 US1 的获取命令（T007 验证依赖源码已落位）
- **US3 (P2)**: 需 US1；与 US2 无文件冲突
- **US4 (P2)**: 需 US1（fetch 之后才有目录集合可断言）

### Within Each User Story

- 契约先行（按 contracts/ 实现并断言）
- 实现 → ctest 接入 → quickstart 对应节演练
- Checkpoint 通过后再进入下一故事

### Parallel Opportunities

- Phase 1: T001 与 T002 并行（不同文件）
- Phase 2–5: US2 与 US3/US4 可并行（前者改 cmake/urpc-deps.cmake，
  后者新增 tools/test/*）
- 示例：T005（重写 urpc-deps）与 T008（单源守护）并行

---

## Parallel Example: US2 + US3

```bash
# 不同文件面，可并行：
Task: "T005 [US2] 重写 cmake/urpc-deps.cmake"
Task: "T008 [US3] 单源守护用例 tools/test/single_source.cmake"
```

---

## Implementation Strategy

### MVP First（US1 + US2 = 源码化闭环）

1. 完成 Phase 1: 清单 + gitignore/README
2. 完成 Phase 2: US1 获取命令（幂等可验证）
3. 完成 Phase 3: US2 构建消费（离线/门卫契约可验证）
4. **STOP and VALIDATE**：quickstart §1–§3 全过 → MVP

### Incremental Delivery

1. Setup → 清单就位
2. +US1 → 获取能力（可独立交付给构建者）
3. +US2 → 完整闭环（配置零网络）
4. +US3/US4 → 治理与边界守护
5. Polish → 文档同步 + 全量走查

---

## Notes

- [P] = 不同文件且无未完成依赖
- [Story] 标签映射 spec.md 用户故事，便于追溯
- 迁移注意：US2 完成后旧 build/ 目录（含 FetchContent _deps 缓存）
  必须删除重建（T007）
- 001 的后续任务（T004+）在新机制上继续；其 T002 已由本特性取代
- 每任务或逻辑组完成后提交；Checkpoint 处停下独立验证
