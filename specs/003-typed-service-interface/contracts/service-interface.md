# Contract: 类型化服务接口（生成物 + 注册/代理公共形态）

对应 spec FR-001..014。本契约描述**用户可见的编程面**：生成物形态、
注册与代理的使用契约。接口契约而非最终头文件排版；C++17；无异常穿越
边界；所有错误经 `Status` 表达。

## 1. 生成物（`--urpc_out`，以 example.EchoService 为例）

### 服务端纯虚接口（用户继承它实现业务）

```cpp
// 生成：<file>.service.h — namespace urpc::gen::<proto_package>
class IEchoService {
 public:
  virtual ~IEchoService() = default;

  // 每个远程方法一个纯虚成员；未重写 = UNIMPLEMENTED 兜底（FR-004）
  virtual void Echo(ServerContext& ctx,
                    const example_EchoRequest* req,
                    UnaryDone<example_EchoResponse> done) {
    done(Status(StatusCode::kUnimplemented, "Echo not implemented"), nullptr);
  }
  virtual void SlowEcho(ServerContext& /*ctx*/,
                        const example_EchoRequest* /*req*/,
                        UnaryDone<example_EchoResponse> done) {
    done(Status(StatusCode::kUnimplemented, "SlowEcho not implemented"), nullptr);
  }

  // 方法表（注册与契约测试消费；与 .proto 方法集一一对应）
  static constexpr MethodDescriptor kMethods[] = { /* ... */ };
};
```

### 客户端代理（继承同一接口）

```cpp
class EchoServiceProxy : public IEchoService {
 public:
  explicit EchoServiceProxy(Channel* channel);   // 业务面最小构造
  explicit EchoServiceProxy(Client* client);     // 控制面构造（等价路由）

  // 异步主形态（任意线程；回调恰好一次；返回 call_id 可取消）
  uint64_t EchoAsync(const example_EchoRequest* req, uint64_t timeout_ms,
                     std::function<void(Result<example_EchoResponse>)> done) override;

  // 同步便捷形态（事件循环线程内 → 快速失败 INTERNAL）
  Result<example_EchoResponse> Echo(const example_EchoRequest* req,
                                    uint64_t timeout_ms);
  // SlowEcho 同构
};
```

### 生成物契约（不变式）

- 接口与代理出自**同一份 .proto、同一次构建**（两端契约同源，FR-002）。
- 方法集合与 .proto 严格一致；描述变更 → 重新构建即更新（编译器背书，
  SC-002）。
- 命名规则：`I<服务名>` / `<服务名>Proxy`；命名空间
  `urpc::gen::<proto package>`（与用户类型隔离）。
- 生成代码不包含业务逻辑；可读、可 include、随标准构建产出（FR-008）。
- 生成物仅消费既有公共类型（upb 消息、Status/Result/ServerContext/
  UnaryDone/Channel/Client）——不引入新公共概念（FR-007）。

## 2. 服务端注册契约

```cpp
// 一次注册发布该服务全部方法（FR-003）
class MyEchoService : public urpc::gen::example::IEchoService {
  void Echo(ServerContext& ctx, const example_EchoRequest* req,
            UnaryDone<example_EchoResponse> done) override;
  // SlowEcho 未重写 → UNIMPLEMENTED（FR-004）
};

auto server = Server::BuildAndStart(opts);
MyEchoService impl;
Status st = RegisterService(*server, impl);     // 生成文件内提供的辅助
// st 失败场景：同一服务名重复注册（明确错误，零副作用）
```

- 注册引用不拥有：`impl` 生存期必须覆盖服务运行期（与 gRPC 一致）。
- Start 前后均可注册（动态注册语义保留）。
- 业务方法内抛异常：该调用以 INTERNAL 结束、服务进程存活（FR-013）。
- 调用上下文能力不降级：`ctx.IsCancelled()/OnCancel()/TimeRemainingMs()`
  语义与 001 完全一致（FR-005）。

## 3. 客户端三分契约（FR-009/010）

```cpp
auto channel = Channel::Connect("127.0.0.1:50051");   // 连接
Client client(channel);                                // 控制面（策略挂载点）
EchoServiceProxy proxy(client);                        // 业务面

auto r = proxy.Echo(req, 3000);        // 同步（timeout_ms；0=不限）
proxy.EchoAsync(req2, 0, [](auto r){ /*异步*/ });       // 异步
```

- **Channel**＝连接（target/建立/关闭）。关闭后其上全部代理的后续调用
  立即 UNAVAILABLE（FR-009）。
- **Client**＝控制面（Options、后续策略挂载）。业务接口不依赖其具体
  形态即可完成全部业务场景（FR-010）。
- **Proxy**＝业务面：仅业务方法，无 connect/close 等连接管理成员
  （US5-2 的审查判据）；无状态 → 多线程并发安全（FR-006）。
- deadline：`timeout_ms` 经 `grpc-timeout` 传播，远端可感知取消
  （FR-012 线协议行为不变）。

## 4. 兼容与迁移契约（FR-014）

- 既有 `RegisterUnaryFor<M>` / `Channel::Call/CallAsync<M>` 入口本期
  **保留且继续可用**；新旧风格可共存（存量测试不改动即可通过）。
- echo 示例与 api 层新增测试迁移到新接口；示例成为新接口的活文档
  （US4）。

## 5. 错误与边界行为汇总

| 场景 | 行为 | 契约来源 |
|------|------|----------|
| 调用未重写方法 | 客户端收 UNIMPLEMENTED | FR-004 |
| 同服务名重复注册 | 注册失败，明确错误 | FR-003 |
| 业务方法抛异常 | 该调用 INTERNAL；进程存活 | FR-013 |
| 事件循环线程内同步调用 | 立即 INTERNAL（快速失败） | 001 语义延续 |
| Channel 已关闭后调用 | 立即 UNAVAILABLE | FR-009 |
| timeout_ms 到期 | DEADLINE_EXCEEDED（双端感知） | FR-012/US2-4 |
| 消息超过尺寸上限 | RESOURCE_EXHAUSTED（与现行为一致） | Edge Cases |
| 空服务（无方法） | 空接口可生成可注册；无调用面 | Edge Cases |
