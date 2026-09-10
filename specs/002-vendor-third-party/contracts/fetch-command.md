# Contract: 获取命令行为（tools/fetch_third_party.cmake）

调用形态（跨平台唯一入口）：

```sh
cmake -P tools/fetch_third_party.cmake
```

## 行为契约

| 契约 | 对应 |
|------|------|
| 读取 `third_party/versions.cmake`（唯一输入；不改写它） | FR-004 |
| 对每个清单依赖：标记匹配 → 跳过；否则下载 → SHA256 校验 → 解压至 `third_party/<name>/`（剥离归档顶层目录）→ 写 `.urpc-version` 标记 | FR-001/002/006 |
| 标记缺失或不匹配的既有目录：整体删除后重新获取（清单为准） | FR-002、边界情形 |
| 单依赖失败：报告依赖名与原因，继续处理其余依赖；任一失败则最终退出码非 0；已就位依赖保持可用 | 边界情形（续传式重试） |
| 全部就位：退出码 0，输出汇总 `fetched=<n> skipped=<m>` | SC-003 |
| 不触碰 Python 依赖与 `third_party/` 之外的任何路径 | FR-007 |
| 不需要网络以外的前置工具（解压用 CMake 内建；下载失败时若系统有 curl 可作重试通道，但不是前置条件） | 边界情形（无 Python/无 bash 可用） |
| 幂等：连续执行，第二轮 fetched=0 skipped=6、文件树零变化 | SC-003 |

## 输出与退出码

- 每依赖一行状态：`[fetch] <name> <version> ...`（下载/校验/解压/跳过）。
- 失败行包含依赖名、阶段（download/verify/extract）与原因。
- 退出码：0 = 全部就位；非 0 = 存在失败依赖。

## 明确的非目标

- 不做依赖版本解析/升级推理（升级 = 人工改清单后重跑）。
- 不做并行下载（顺序足够；复杂度不值当）。
- 不清理 `third_party/` 之外的构建目录。
