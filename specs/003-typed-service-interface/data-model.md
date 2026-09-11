# Data Model: 类 gRPC 的类型化服务接口

本特性为接口层重塑，无持久化数据；数据模型描述**生成期与运行期的
关键实体及其关系**。字段类型用概念类型（不绑定实现细节）。

## 实体总览

```text
.proto 服务描述（单一事实来源）
        │ protoc --urpc_out（生成期，确定性）
        ▼
┌─────────────────────────────────────────────┐
│ 生成文件 <file>.service.h/.cc                │
│  ├─ urpc::gen::<pkg>::IXxxService   纯虚接口 │
│  │    └─ kMethods[] 静态方法表               │
│  ├─ urpc::gen::<pkg>::XxxServiceProxy 代理   │
│  └─ RegisterService(Server&, IXxxService&)   │
└─────────────────────────────────────────────┘
        │ 编译期绑定                    │ 编译期绑定
        ▼                              ▼
  用户业务类                       客户端调用方
  class XxxService                 auto proxy = client.Proxy<...>()
       : public IXxxService              │
        │ 实例引用注册                    │ 方法调用
        ▼                              ▼
  urpc::Server ◄────── 线协议（不变） ──► urpc::Client ─► Channel
```

## 生成期实体

### MethodDescriptor（方法描述符，生成接口的静态成员）

| 字段 | 类型 | 说明 | 来源 |
|------|------|------|------|
| name | 字符串视图 | 方法名（如 `Echo`） | proto method.name |
| path | 字符串视图 | `/package.Service/Method` | 推导 |
| req_parse | 函数指针 | bytes → upb 请求消息 | upb 生成符号 |
| res_encode | 函数指针 | upb 响应消息 → bytes | upb 生成符号 |

**不变式**：`kMethods` 与 .proto 中 service 的方法集合**一一对应、
顺序稳定**（proto 字段/方法序号稳定 → 生成确定性 → 金样可对照）。

**验证规则**：编译期 static_assert 数量与名称集合匹配（SC-002 机制）。

### 生成的接口类 IXxxService

| 成员 | 形态 | 说明 |
|------|------|------|
| `virtual void <Method>(ServerContext&, const Req*, UnaryDone<Res>)` | 纯虚 ×N | 每个远程方法一个；签名与 001 UnaryHandlerFn 同构 |
| 未重写默认实现 | 内联体 | `done(UNIMPLEMENTED)` 兜底（FR-004） |
| `kMethods` | static | 方法表（注册与契约测试消费） |
| 虚析构 | 默认 | 经引用注册、用户拥有（research §3） |

### 生成的代理 XxxServiceProxy : public IXxxService

| 成员 | 形态 | 说明 |
|------|------|------|
| `XxxServiceProxy(Channel*)` / `(Client*)` | 构造 | 绑定连接/控制面（FR-006/009） |
| `<Method>Async(req, timeout_ms, done)` → call_id | 覆写 | 转调 ProxyBase → ChannelCallRaw（异步主形态） |
| `<Method>(req, timeout_ms)` → Result\<Res\> | 覆写 | 同步便捷形态；事件循环线程内快速失败 |

**状态**：无业务状态（仅持有 Channel*/Client* 不可变引用）→ 天然
线程安全（FR-006）。

## 运行期实体与关系

### 职责三分（US5 / FR-009/010）

| 实体 | 职责 | 拥有/引用 | 生命周期 |
|------|------|-----------|----------|
| Channel | 连接：target、建立、关闭 | 专属事件循环线程 | shared_ptr；关闭后代理调用 → UNAVAILABLE |
| Client | 控制面：Options 挂载 + 代理工厂 | 引用 Channel | 用户持有 |
| XxxServiceProxy | 业务面：仅业务方法 | 引用 Channel/Client | 值语义/临时均可 |
| Server | 宿主：接受实例注册 | 引用业务实例（不拥有） | 服务运行期 ≥ 实例生存期（用户保证） |
| XxxService（用户） | 业务实现 | 继承 IXxxService | 用户拥有 |

### 状态迁移（关键路径）

```text
Channel: Idle → Connecting → Ready → Broken(closed)
  关闭触发: 代理在途调用 → 各自失败回调一次; 后续调用 → 立即 UNAVAILABLE

Server 注册: Start 前/后均可 RegisterService(impl)
  同服务名二次注册 → 拒绝（错误状态，零副作用）
  未重写方法被调 → 客户端收 UNIMPLEMENTED（服务端兜底响应）

调用上下文（每次调用）: Active → (Cancelled | Deadlined | Responded | Excepted→INTERNAL)
  恰好一次 done 回调（含异常路径 FR-013）
```

## 验证规则汇总（映射 FR）

- FR-001/002：接口/代理由同一描述生成、同一契约（编译期 + 金样）。
- FR-003：注册整体性 + 重名拒绝（行为测试）。
- FR-004：默认实现 UNIMPLEMENTED（行为测试）。
- FR-005：ServerContext 能力不降级（取消/deadline 测试复用 001 用例形态）。
- FR-006/009：代理并发 + Channel 关闭语义（行为测试）。
- FR-012：互操作全绿（既有套件）。
