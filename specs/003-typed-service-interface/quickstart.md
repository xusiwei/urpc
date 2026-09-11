# Quickstart: 类型化服务接口验证指南

端到端验证本特性按预期工作。前置：CMake ≥ 3.21、C++17 编译器、
网络回环可用；依赖已 vendored（`cmake -P tools/fetch_third_party.cmake`）。

验证场景与 [contracts/service-interface.md](contracts/service-interface.md)
一一对应；实体与状态语义见 [data-model.md](data-model.md)。

## 1. 构建与全量回归（US4 / FR-008/012）

```bash
cmake --preset release
cmake --build --preset release
ctest --preset verify          # 单元 + 集成 + 生成物契约 + 示例端到端
```

**预期**：全部测试通过，重点新增：
- `urpc-api`（含 test_service_codegen：生成物形态/方法表 static_assert/
  金样片段、未重写 UNIMPLEMENTED、重复注册拒绝）
- `urpc-api`（含 test_typed_e2e：接口实现 + 代理 loopback 全场景）
- `examples-echo-e2e`（迁移后经新接口运行，零方法名字符串）
- Linux/macOS/Windows 三平台一致全绿（CI）。

## 2. 手工体验：接口继承 + 代理调用（US1/US2 活文档）

```bash
./build/release/examples/echo/urpc_echo_server 127.0.0.1:50051 &
./build/release/examples/echo/urpc_echo_client 127.0.0.1:50051
```

**预期**：客户端经 `EchoServiceProxy` 完成回显校验，退出码 0；服务端
日志可见每个调用的开始/结束与状态码。源码形态即验证目标（SC-001/004）：
- `echo_server_main.cpp`：`class EchoServiceImpl : public
  urpc::gen::example::IEchoService { ... }` + `RegisterService(server, impl)`
- `echo_client_main.cpp`：`Channel::Connect` → `Client` →
  `EchoServiceProxy` → `proxy.Echo(...)`
- 两文件中 `grep -c "EchoService\"" 应为 0（无方法名字符串）。

## 3. 接口演进由编译器背书（US3 / SC-002）

```bash
# 在 examples/echo/echo.proto 的 service 内新增:  rpc Ping(PingRequest) returns (PingResponse);
# 并补消息定义，然后：
cmake --build --preset release
```

**预期**：构建失败于 `EchoServiceImpl`（缺失 Ping 重写），错误指向
生成接口的纯虚方法；实现 Ping 并改回后构建恢复、调用即通。

## 4. 互操作不回退（FR-012）

```bash
ctest --preset interop --timeout 300    # gRPC Python 对端（需 grpcio）
```

**预期**：双向互通全部通过（线协议行为与本特性前一致）。

## 5. 生成器确定性（FR-008 / SC-002）

```bash
cmake --build --preset release   # 连续两次
# 对比两次 build/release/gen/echo/echo.service.h 内容
```

**预期**：字节一致（确定性输出；金样对照依赖此性质）。

## 6. 成功标准对照

| SC | 验证点 | 本指南章节 |
|----|--------|-----------|
| SC-001 | 全方法经接口/代理往返、零方法名字符串 | §1/§2 |
| SC-002 | 描述变更 → 编译期提醒 + 一键再生成 | §3 |
| SC-003 | 三平台构建/测试/示例一次通过；互操作全绿 | §1/§4 |
| SC-004 | 示例服务端用户代码 ≤ 现形态 70% | §2 源码审查 |
| SC-005 | 依赖面零变化 | §1（构建即证：无新 fetch） |
