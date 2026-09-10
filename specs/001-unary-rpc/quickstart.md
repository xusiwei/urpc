# Quickstart: Unary Request/Response 验证指南

端到端验证本特性按预期工作。前置：CMake ≥ 3.21、C++17 编译器
（GCC ≥ 9 / Clang ≥ 10 / MSVC 2019+）、网络回环可用。依赖
（libuv/nghttp2/protobuf-upb/GoogleTest/benchmark）经 FetchContent
自动获取，亦可预先安装系统包（find_package 优先）。

## 1. 构建与单元/集成验证

```bash
cmake --preset release          # 标准预设（三平台一致）
cmake --build --preset release
ctest --preset verify           # 单元 + 集成 + 示例端到端
```

**预期**：全部测试通过（含 `urpc-core-*`、`urpc-api-*`、
`examples-echo`）；零手工步骤（SC-002）。

## 2. 运行端到端示例（US3 / FR-008）

```bash
./build/release/examples/echo/urpc_echo_server 127.0.0.1:50051 &
./build/release/examples/echo/urpc_echo_client 127.0.0.1:50051
```

**预期**：客户端循环调用 `example.EchoService/Echo` 并校验回显，
打印成功摘要，退出码 0；服务端日志可见 call 开始/结束事件与状态码 0
（验证 FR-011 日志可见性）。

## 3. 性能基准与基线留档（US7 / SC-003）

```bash
./build/release/libs/core/bench/urpc_bench_unary       # 串行 RTT + 并发吞吐
# 结果以 JSON 追加留档（tools/ 约定目录），随后：
ctest --preset bench   # 或脚本重跑并对比基线
```

**预期**：1KiB 消息回环——串行 p50 ≤ 300µs、p99 ≤ 1.5ms；4 在途
吞吐 ≥ 10k ops/s；多轮中位波动 ≤ 10% 且每轮留档（research.md §1）。

## 4. 官方 gRPC Python 互通（US5 / SC-004）

```bash
python3 -m pip install -r interop/python/requirements.txt   # grpcio 固定版本
ctest --preset interop   # 四象限：官方客户端×urpc 服务端 / urpc 客户端×官方服务端
```

**预期**：成功场景消息语义一致；错误场景状态码正确透传
（UNIMPLEMENTED、DEADLINE_EXCEEDED 各至少一例）。

## 5. 30 分钟上手复刻（SC-001）

按 `contracts/server-api.md` 与 `contracts/client-api.md` 的最小示例，
在新目录中实现一个 `ToUpper` 一元方法并用客户端调用成功——全程只需
公共头文件与本指南，即验证「30 分钟闭环」成功标准。

## 已知边界

- 明文直连：无 TLS/压缩/流式/重试（spec 假设，后续特性）。
- 同步调用不得在框架事件循环线程内使用（快速失败，FR-002）。
- 消息默认上限 4MiB（可配置，FR-007）。
