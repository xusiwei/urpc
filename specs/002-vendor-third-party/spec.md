# 特性规格：三方依赖源码化（third_party/ 统一组织）

**Feature Branch**: `002-vendor-third-party`

**Created**: 2026-09-10

**Status**: Draft

**Input**: 用户描述："项目三方库的组织形式改一下，改成源码下载到
third_party/ 目录。包括 libuv、nghttp2、protobuf、googltest、benchmark
等所有项目C++源码依赖的三方库(Python脚本的依赖库不需要)。"

## Clarifications

（无——本特性由明确的构建组织变更请求直接驱动，默认值见假设章节）

## 用户场景与测试（User Scenarios & Testing）

### User Story 1 - 一条命令获取全部依赖源码 (Priority: P1)

任何构建者（开发者/CI）在全新检出仓库后，执行一条获取命令，即把全部
C++ 三方依赖（libuv、nghttp2、protobuf、abseil、googletest、benchmark）
的固定版本源码下载到 `third_party/<名称>/` 目录；已存在且版本匹配的
依赖自动跳过，命令可安全重复执行。

**Why this priority**: 源码就位是一切后续构建的前提；幂等与版本固定是
可复现构建的根基。

**Independent Test**: 删除 `third_party/` 后执行获取命令，断言目录结构
与版本符合清单；紧接着重复执行一次，断言零变化且退出码为 0。

**Acceptance Scenarios**:

1. **Given** 全新检出且 `third_party/` 不存在，**When** 执行获取命令，
   **Then** 全部依赖按清单版本落位到 `third_party/`，命令成功退出。
2. **Given** `third_party/` 已按当前清单就位，**When** 再次执行获取
   命令，**Then** 无重复下载、无文件变更、退出码 0（幂等）。
3. **Given** 下载中途被中断，**When** 重新执行获取命令，
   **Then** 残留的不完整目录被识别并重新获取，最终完整落位。

---

### User Story 2 - 构建只从 third_party/ 消费源码 (Priority: P1)

构建系统在配置与编译期完全从 `third_party/` 目录取依赖源码，配置阶段
不再访问网络；依赖目录缺失时，配置立即失败并给出明确的获取指引，
而不是隐式联网下载或报模糊错误。

**Why this priority**: 与 US1 共同构成"源码下载到 third_party/"的完整
闭环；离线可构建是可复现性与嵌入友好的直接收益。

**Independent Test**: 在断网（或禁止出网的）环境对已就位的 `third_party/`
执行完整配置与构建，断言成功；移任一依赖目录后重新配置，断言得到
带指引的明确失败。

**Acceptance Scenarios**:

1. **Given** `third_party/` 完整就位，**When** 在无网络环境执行配置与
   构建，**Then** 全量构建成功，配置期无任何网络访问。
2. **Given** 某依赖目录缺失，**When** 执行配置，**Then** 配置以明确
   错误停止，错误信息包含获取命令指引。

---

### User Story 3 - 依赖清单单一事实源 (Priority: P2)

全部依赖的名称、版本、来源与许可证集中于一个清单文件；升级任何依赖
只改清单这一处，获取与构建随之生效，评审面收敛到单文件差异。

**Why this priority**: 对齐宪法原则 V「版本固定并经评审」；单文件升级
路径使依赖治理可执行。

**Independent Test**: 修改清单中任一依赖版本→重新获取→重新构建，
断言新版本生效且其余依赖不受影响。

**Acceptance Scenarios**:

1. **Given** 清单声明依赖 X 的版本 A，**When** 获取与构建，
   **Then** `third_party/X` 内容与版本 A 一致，构建产物链接版本 A。
2. **Given** 清单将 X 从 A 改为 B，**When** 重新获取，**Then** X 目录
   更新为版本 B，其余依赖目录零变化。

---

### User Story 4 - Python 依赖保持豁免 (Priority: P2)

互通测试等 Python 脚本依赖（grpcio 等）维持既有依赖方式（requirements
文件 + 包管理器安装），不进入 `third_party/`，也不改变其安装流程。

**Why this priority**: 明确边界、避免范围膨胀；Python 依赖生态与 C++
源码 vendoring 的治理方式不同，混用会抬高两边的成本。

**Independent Test**: 执行依赖获取命令后，断言 `third_party/` 中不出现
任何 Python 包产物；互通脚本仍按 requirements 方式运行。

**Acceptance Scenarios**:

1. **Given** 依赖获取命令执行完成，**When** 检查 `third_party/`，
   **Then** 仅包含清单声明的 C++ 依赖源码目录，无 Python 产物。

### Edge Cases（边界情形）

- 版本清单与磁盘残留不一致（目录存在但版本不匹配）：必须识别并以清单
  为准重新获取，不得静默沿用。
- 部分下载残留（无版本标记的半成品目录）：识别后清理重取。
- 来源不可达：命令以明确错误退出，指明失败的依赖与来源，已成功的
  依赖保持可用（支持续传式重试）。
- 各依赖源码自带的许可证与版权文件必须随源码完整保留（合规审计面）。
- 构建者环境无 Python：C++ 构建路径不依赖 Python 存在。

## 需求（Requirements）

### Functional Requirements

- **FR-001**: 系统 MUST 提供一条获取命令，将全部 C++ 三方依赖（至少
  libuv、nghttp2、protobuf、abseil、googletest、benchmark）的固定版本
  源码下载到 `third_party/<名称>/`。
- **FR-002**: 获取命令 MUST 幂等：已就位且版本匹配的依赖跳过；版本
  不匹配或残留不完整的依赖按清单重新获取。
- **FR-003**: 构建 MUST 仅从 `third_party/` 消费依赖源码；配置期 MUST
  NOT 访问网络；依赖缺失时 MUST 以含获取指引的明确错误停止。
- **FR-004**: 依赖的名称、版本、来源与许可证 MUST 集中于单一清单文件
  维护；获取与构建只读取该清单。
- **FR-005**: `third_party/` 目录内容默认 MUST NOT 入版本库；清单与
  获取脚本 MUST 入库，保证任何环境可复现获取。
- **FR-006**: 依赖完整性 MUST 可校验（对下载内容进行来源与一致性
  校验，防止半成品/错版本静默通过）。
- **FR-007**: Python 脚本依赖 MUST 保持原有依赖方式，不纳入
  `third_party/` 与本机制。
- **FR-008**: 获取与构建流程 MUST 在全部受支持平台（Linux、macOS、
  Windows）可用。
- **FR-009**: 迁移 MUST 移除旧的配置期联网获取路径（构建图内不再存在
  任何隐式下载行为）。

### Key Entities（关键实体）

- **依赖清单（Dependency Manifest）**: 全部 C++ 依赖的名称、版本、
  来源地址、校验信息与许可证声明的集合；单一事实源。
- **获取命令（Fetch Command）**: 读取清单、下载/校验/落位源码的幂等
  工具；跨平台。
- **third_party/<名称>（Vendored Source）**: 单个依赖的源码目录，
  含其原始许可证文件；版本与清单一致。

## 成功标准（Success Criteria）

### Measurable Outcomes

- **SC-001**: 全新检出后，依序执行「获取命令 + 配置 + 构建」两条到
  三条命令即完成全量构建；配置与编译阶段零网络访问。
- **SC-002**: 同一清单在全部受支持平台产出相同的依赖版本组合
  （清单即版本事实源）。
- **SC-003**: 获取命令连续执行两轮，第二轮零下载、零文件变更、
  退出码 0。
- **SC-004**: 升级任一依赖只需修改清单单文件，重新获取后构建即切换
  到新版本，其余依赖目录与构建行为不受影响。

## 假设（Assumptions）

- `third_party/` 内容为工作产物，默认被版本库忽略；如未来希望「提交
  源码入仓」的完全离线克隆体验，可作为清单的一个开关另行演进（本特性
  不做）。
- abseil 作为 protobuf 宿主编译器的传递构建依赖，随本机制一并纳入
  `third_party/`（用户列举的"所有 C++ 源码依赖"包含传递依赖）。
- 宿主 protoc 继续从 vendoring 的 protobuf 源码构建，不再使用任何
  预编译产物下载路径。
- 已有的系统包优先（find_package）路径随本变更移除：依赖以 vendoring
  源码为唯一来源，换取构建一致性（宪法原则 V 允许源内 vendoring）。
- 在途的 001（unary-rpc）特性将随本特性落地同步迁移其依赖组织
  （T002 的实现由新机制取代），不改变 001 的功能需求。
