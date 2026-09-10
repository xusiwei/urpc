# Phase 1 Data Model: 三方依赖源码化

## 实体

### 依赖清单项（ManifestEntry）

| 字段 | 类型 | 约束 |
|------|------|------|
| name | 标识符 | 小写；目录名与变量名派生源（libuv、nghttp2、protobuf、abseil、googletest、benchmark） |
| version | 字符串 | 与来源 tag 一致；非空 |
| url | URL | codeload 归档（含 tag），由 version 派生 |
| sha256 | 十六进制 64 字符 | 下载内容校验锚点；清单中唯一 |
| license | 标识符 | SPDX 风格（MIT / Apache-2.0 / BSD-3-Clause…）；源码目录内须存在对应许可证文件 |

关系：Manifest（清单文件）1..n ManifestEntry；ManifestEntry 1..1
VendoredSource（获取后）。

校验：name 集合必须覆盖「全部 C++ 构建期依赖」；protobuf ↔ abseil
版本配对约束（abseil 版本须为对应 protobuf 源钦定版本）。

### 源码目录（VendoredSource）

| 字段 | 说明 | 约束 |
|------|------|------|
| dir | third_party/<name>/ | tarball 解压剥离顶层目录后的内容 |
| marker | .urpc-version 文件 | 两行：version、sha256；由获取命令在成功后写入 |
| license_file | 随源码保留 | 不得删除/改名 |

不变量：marker 存在且与清单一致 ⇔ 目录被视为就位；其余状态
（无 marker、marker 不匹配）一律视为未就位。

### 获取执行（FetchRun）

对每个依赖的状态迁移：

```text
ABSENT ──下载──▶ DOWNLOADED ──校验──▶ VERIFIED ──解压──▶ EXTRACTED ──写标记──▶ READY
MATCHED（marker 与清单一致，跳过全部步骤）
MISMATCH（目录存在但 marker 缺失/不匹配）─▶ 清理目录 ─▶ ABSENT
```

规则（对应 FR-002 / 边界情形）：
- 单依赖失败不回滚其他已 READY 的依赖（续传式重试）。
- 下载/校验失败：非零退出，报告依赖名与原因。
- 全部 READY：退出码 0，报告 fetched/skipped 计数。

### 构建门卫（BuildGuard）

| 字段 | 说明 |
|------|------|
| 检查时机 | cmake/urpc-deps.cmake 被处理时（配置期最前段） |
| 判据 | 同 VendoredSource 不变量 |
| 失败动作 | FATAL_ERROR，消息含缺失依赖名与获取命令原文（见 contracts/build-guard.md） |

不变量：配置期代码路径不存在任何下载原语（file(DOWNLOAD)/FetchContent），
即离线可配置是结构性保证而非运行时开关。

## 验证规则汇总（对应需求）

- 幂等：连续两轮 FetchRun，第二轮全部 MATCHED、树零变化（FR-002/SC-003）
- 完整性：sha256 不匹配 → 拒绝落位（FR-006）
- 离线：依赖就位后断网配置构建成功（FR-003/SC-001）
- 缺失指引：删任一目录 → 配置失败且含命令指引（FR-003 场景 2）
- 单文件升级：清单改版本 → 仅该依赖目录变化（FR-004/SC-004）
- Python 豁免：third_party/ 无 Python 产物（FR-007）
