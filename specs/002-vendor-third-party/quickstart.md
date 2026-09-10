# Quickstart: 三方依赖源码化验证指南

前置：CMake ≥ 3.21；获取阶段需要网络（构建阶段不需要）。无需 Python、
bash 专属工具或系统包管理器。

## 1. 获取依赖源码（US1）

```sh
cmake -P tools/fetch_third_party.cmake
```

**预期**：六个依赖（libuv、nghttp2、protobuf、abseil、googletest、
benchmark）落位 `third_party/<name>/`；汇总输出 `fetched=6 skipped=0`；
退出码 0。再次执行 → `fetched=0 skipped=6`，`third_party/` 文件树零
变化（幂等，SC-003）。

## 2. 构建（US2 / SC-001）

```sh
cmake --preset release
cmake --build --preset release
ctest --preset verify
```

**预期**：配置期零网络访问（可在断网环境执行同样命令验证）；全量
构建成功；`vendor-third-party-idempotent` 冒烟测试通过。

## 3. 缺失依赖的明确指引（US2 场景 2）

```sh
rm -rf third_party/libuv
cmake --preset release   # 预期失败
```

**预期**：配置以 FATAL_ERROR 停止，错误消息包含 `libuv`、缺失版本与
`cmake -P tools/fetch_third_party.cmake` 指引；随后重跑获取命令即恢复
（仅重取 libuv，其余 skipped）。

## 4. 清单升级演练（US3 / SC-004）

```sh
# 编辑 third_party/versions.cmake 中某依赖的 VERSION/URL/SHA256
cmake -P tools/fetch_third_party.cmake
cmake --build --preset release
```

**预期**：仅该依赖目录更新为新版本，其余依赖目录零变化；构建链接
新版本。（首次演练建议用同版本哈希改写再改回，避免真实升级。）

## 5. Python 依赖豁免确认（US4）

**预期**：`third_party/` 内无任何 Python 产物；`interop/python` 的
requirements 方式不受影响（`pip install -r interop/python/requirements.txt`
行为不变）。

## 已知边界

- `third_party/` 源码不入库（.gitignore 忽略，仅 versions.cmake 与
  README 例外）；新环境首次构建前必须执行获取命令。
- 升级依赖的唯一路径是修改 `third_party/versions.cmake`（单文件评审）。
- abseil 版本必须与 protobuf 源钦定版本配对（清单不变量）。
