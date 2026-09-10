# Phase 0 Research: 三方依赖源码化

决策 → 理由 → 备选。SHA256 均为本会话实测锚定。

## 1. 获取工具形态

**Decision**: `cmake -P tools/fetch_third_party.cmake`（CMake script
mode）。下载用 `file(DOWNLOAD)`（回退系统 curl），解压用
`file(ARCHIVE_EXTRACT)`，标记用 `file(WRITE)`。

**Rationale**: 零第三方依赖（宪法 V）；三平台同一命令（宪法 III），
Windows 无需 bash/tar；与构建系统同语言，清单可被直接 `include()`。

**Alternatives**: bash 脚本（否：Windows 体验差）；Python 脚本（否：
C++ 构建路径不得依赖 Python 存在，spec 边界情形）；git submodule
（否：早前目录结构讨论已否决，且与「下载源码」语义不符）。

## 2. 清单单一事实源

**Decision**: `third_party/versions.cmake`，每依赖四个变量：
`URPC_TP_<NAME>_VERSION / _URL / _SHA256 / _LICENSE`。获取脚本与
`cmake/urpc-deps.cmake` 共同 include 此文件。

**Rationale**: FR-004 单文件评审面；CMake 语法可被两侧零成本消费，
无需引入 TOML/JSON 解析。

**Alternatives**: JSON/TOML 清单（否：需解析依赖或额外工具）；
清单内嵌获取脚本（否：违背「清单与工具分离、清单入库评审」）。

## 3. 目录布局与幂等标记

**Decision**: tarball 解压剥离顶层目录后落位 `third_party/<name>/`；
成功完成后写入 `third_party/<name>/.urpc-version`（内容：版本行 +
SHA256 行）。幂等判据 = 标记存在且与清单一致；标记缺失（半成品/手工
解压）或版本不匹配 → 删除目录重取。

**Rationale**: FR-002/FR-006；标记随目录走，天然支持「删一个依赖
单独重取」与升级时的整目录替换。

**Alternatives**: 集中式 state 文件（否：目录删除/手工操作会失同步）；
仅比对目录存在性（否：无法识别半成品与错版本）。

## 4. 完整性校验

**Decision**: SHA256 随清单固定；下载后先校验再解压；解压成功才写
标记。校验失败即退出非零并保留 tarball 供诊断。

**Rationale**: FR-006；防半成品与来源漂移。实测锚点：

| 依赖 | 版本 | SHA256 |
|------|------|--------|
| libuv | 1.48.0 | 8c253adb0f800926a6cbd1c6576abae0bc8eb86a4f891049b72f9e5b7dc58f33 |
| nghttp2 | 1.65.0 | bcf08112bd583f8543776d086dcdede159b87e1261a36e6ae1d931c812a3ca70 |
| protobuf | 30.2 | 07a43d88fe5a38e434c7f94129cad56a4c43a51f99336074d0799c2f7d4e44c5 |
| abseil | 20250127.0 | 16242f394245627e508ec6bb296b433c90f8d914f73b9c026fddb905e27276e8 |
| googletest | 1.15.2 | 7b42b4d6ed48810c5362c265a17faebe90dc2373c885e5216439d37927f02926 |
| benchmark | 1.9.1 | 32131c08ee31eeff2c8968d7e874f3cb648034377dfc32a4c377fa8796d84981 |

**Alternatives**: 仅版本号比对（否：不防传输损坏与来源篡改）；
GPG 签名（否：引入密钥管理，超出本特性必要复杂度）。

## 5. 构建消费与离线保证

**Decision**: 重写 `cmake/urpc-deps.cmake`：
①逐依赖校验 `third_party/<name>/.urpc-version` 与清单一致，否则
`message(FATAL_ERROR "... run: cmake -P tools/fetch_third_party.cmake")`；
②`add_subdirectory(third_party/<name>)` 消费（libuv/nghttp2/gtest/
benchmark/abseil/protobuf）；③upb 子集与宿主 protoc 的现有构建逻辑
平移为从 `third_party/protobuf` 取源；④删除全部 FetchContent 声明与
find_package 优先路径——vendoring 为唯一来源。构建图内零
`file(DOWNLOAD)`/FetchContent。

**Rationale**: FR-003/FR-009；spec 假设「系统包优先路径移除」。
上层目标名不变（uv_a、nghttp2_static、urpc_upb、protoc、GTest::gtest、
benchmark::benchmark），libs/* 的 CMakeLists 零改动。

**Alternatives**: 保留 find_package 优先（否：与用户决策不符，双路径
稀释可复现性）；配置期自动触发获取（否：违背「配置期零网络」，
隐藏副作用）。

## 6. 来源选择

**Decision**: 统一使用 codeload 归档
（`https://github.com/<org>/<repo>/archive/refs/tags/<tag>.tar.gz`），
不使用 release 资产。

**Rationale**: 本环境实测 release 资产 CDN（objects.githubusercontent.
com）GET 不稳定，codeload 稳定；codeload 内容由 tag 唯一决定，
配合 SHA256 可复现。

**Alternatives**: release 资产（否：见上）；git clone --depth 1
（否：需 git 且较慢，Windows 附加要求）。

## 7. 版本库策略

**Decision**: `.gitignore` 增加 `third_party/*`，反向保留
`!third_party/versions.cmake` 与 `!third_party/README.md`。

**Rationale**: FR-005；源码不入库（体积与更新噪音），清单+脚本入库
保证任何环境可复现获取。

**Alternatives**: 源码提交入仓（否：spec 假设明确列为后续可选演进，
不在本特性）。

## 8. 验证方式

**Decision**: ①ctest 冒烟 `vendor-third-party-idempotent`：重复执行
获取命令，断言退出码 0 且报告 fetched=0/skipped=6；②契约用例：删除
单个依赖目录后配置必须失败且错误含获取命令字样；③quickstart 手册
演练含断网构建与清单升级两个场景。

**Rationale**: 宪法 IV；幂等与错误契约可自动化，断网/升级为低频
手册演练。

**Alternatives**: 全部手工验证（否：幂等性回归应被门禁守护）。

## 9. 与 001（unary-rpc）的衔接

**Decision**: 本特性落地后，001 的 T002（依赖封装）实现由新机制
取代——001 后续任务（T004+）在迁移后的构建系统上继续，不需要回滚
任何已交付代码；001 的 research.md §2 决策由本文件 supersede（规格
假设已记录）。

**Rationale**: 构建组织层替换，功能面零影响；避免 001 中途返工。
