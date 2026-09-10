# Phase 1 Data Model: Unary Request/Response

实体提取自 spec.md 关键实体节与 FR-001~FR-012。域实体与内核内部
实体分开列出；实现形态见 contracts/。

## 域实体（用户可见）

### 服务（Service）

| 字段 | 说明 | 约束 |
|------|------|------|
| name | 服务名（全限定，如 `example.EchoService`） | 非空；同一 Server 内唯一；用于线上路径 `/name/method` |

关系：1 个 Service 包含 1..n 个 Method。

### 方法（Method）

| 字段 | 说明 | 约束 |
|------|------|------|
| service | 所属服务 | — |
| name | 方法名 | 服务内唯一；`/service/name` 为线上唯一路由键 |
| handler | 一元处理器 | 请求一条 → 响应一条或错误状态 |
| request/response 类型 | upb 消息描述 | 编解码错误归为调用级错误，不伤连接 |

校验：同一路径重复注册 MUST 被拒绝（spec 边界情形）。

### 状态（Status）

| 字段 | 说明 | 约束 |
|------|------|------|
| code | 标准 gRPC 状态码 | OK / UNIMPLEMENTED / INTERNAL / DEADLINE_EXCEEDED / RESOURCE_EXHAUSTED / UNAVAILABLE / DATA_LOSS（本特性集合） |
| message | 可选文本 | 人类可读，不含内部控制字符 |

### 服务器（Server）

| 字段 | 说明 | 约束 |
|------|------|------|
| listen_address | 监听地址 | 启动后不可变 |
| services | 已注册服务集 | 支持运行中动态注册（US1 场景 2） |
| max_receive_size | 单消息接收上限 | 默认 4MiB，可配置（FR-007） |
| shutdown_grace | 优雅关闭宽限期 | 可配置（FR-012） |
| state | 运行状态 | STARTING → RUNNING → DRAINING → STOPPED（见状态迁移） |

状态迁移：
- STARTING → RUNNING：绑定+监听成功
- RUNNING → DRAINING：`Shutdown()` 调用（拒新连接/新调用，发 GOAWAY）
- DRAINING → STOPPED：在途调用全部完成，或宽限期耗尽强制取消后

### 通道（Channel）

| 字段 | 说明 | 约束 |
|------|------|------|
| target | 服务端地址 | 创建后不可变 |
| state | 通道状态 | IDLE → CONNECTING → READY → SHUTDOWN |
| max_..._size | 客户端接收上限 | 默认 4MiB，可配置 |
| 并发能力 | 单连接 HTTP/2 多路流 | 代理对象线程安全（FR-005） |

### 调用（Call / CallHandle）

| 字段 | 说明 | 约束 |
|------|------|------|
| method | 目标方法路径 | — |
| request | 请求消息（upb 编码字节） | 长度 ≤ 接收上限 |
| deadline | 截止时间 | 未设置 = 不超时；随调用传播（grpc-timeout） |
| state | 调用状态 | 见下 |
| result | 响应消息或 Status | 终态后恰好一次投递 |

调用状态机：

```text
INITIATED → IN_FLIGHT ──→ COMPLETED（OK，含响应消息）
                │      └→ FAILED（非 OK 状态码）
                ├────────→ DEADLINE_EXCEEDED（截止时间到）
                └────────→ CANCELLED（客户端主动取消/通道关闭→UNAVAILABLE 语义）
```

约束：终态恰好一次；终态后 Handle 只读。

### 消息（Message）

| 字段 | 说明 | 约束 |
|------|------|------|
| bytes | 长度前缀帧去掉 5 字节头后的 protobuf 编码 | 允许零长度（spec 边界情形） |

## 内核内部实体（core 私有）

### Stream（HTTP/2 流 ↔ 调用配对）

| 字段 | 说明 |
|------|------|
| stream_id | HTTP/2 流 ID |
| call | 关联的 Call 上下文（方向：客户端发起/服务端接受） |
| recv_buffer | 接收缓冲（受 max_receive_size 约束，防内存放大） |
| deadline_timer | libuv 定时器（截止时间执行点） |

不变量：一流至多一 Call；Call 终态 ⇒ 流关闭（正常 END_STREAM / RST_STREAM
/ 框架取消），无悬挂（spec 边界：资源不泄漏）。

### Router（方法路由表）

路径 `/service/method` → handler 的只读快照表；动态注册以写锁 +
快照替换实现，读取无锁。

### 事件循环运行体（LoopRunner）

每 Server / Channel 一个专属循环线程；外部线程投递闭包
（uv_async_t 唤醒）；同步调用等待原语挂在投递的未来值上。

## 验证规则汇总（对应需求）

- 路由键唯一性 → 注册期拒绝重复（FR-001，边界情形）
- 消息大小上限 → 流级缓冲上限，超限 RESOURCE_EXHAUSTED（FR-007）
- 截止时间 → 定时器触发取消传播（FR-004，Clarifications #1）
- 状态码集合 → FR-003 枚举闭合
- 终态一次投递 → US2/US6 响应配对断言的基础
- 优雅关闭状态迁移 → FR-012，宽限期后 UNAVAILABLE
