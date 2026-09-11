# Phase 0 Research: 类 gRPC 的类型化服务接口

本文件记录将规格未知项转为实现决策的研究结论。格式：决策 → 理由 →
备选方案。规格（spec.md）无 [NEEDS CLARIFICATION] 遗留；本阶段的
"未知"来自 Technical Context 的实现形态选择。

## 1. 生成器形态：protoc 插件（protoc-gen-urpc，`--urpc_out`）

**Decision**: 以标准 protoc 插件实现，源码放 `generator/`（仓库新顶层
目录，与 tools/ 平级），构建为独立可执行目标 `protoc-gen-urpc`，经
`urpc-deps.cmake` 挂到 vendored protobuf 的构建链（与既有
protoc-gen-upb / protoc-gen-upb_minitable 同一 add_subdirectory 体系、
同一 CodeGeneratorService 机制）。cmake 侧扩展 `urpc_proto_upb()`：
同一份 .proto 一次 protoc 调用同时产出 upb 运行时代码与
`<file>.service.h/.cc`（接口 + 代理 + 桥接三合一，经 `--urpc_out`）。

**Rationale**:
- 插件机制是 protobuf 官方唯一受支持的扩展点；gRPC 自身的
  grpc_cpp_plugin 即此形态，保证与 .proto 生态（工具、语法、版本演进）
  完全兼容（FR-011，SC-002）。
- 与 protoc-gen-upb 并列复用既有构建链 = 零新依赖（原则 V，SC-005）、
  三平台确定性构建（FR-008，宪法 III）。
- 插件拿到的是解析后的完整 DescriptorPool（服务/方法/消息/路径），
  命名与符号推导不需要二次解析。
- **放置在 vendored 树外**（generator/）而不是 third_party/protobuf/
  内：vendored 目录由 SHA256 锚定、refetch 即覆盖（002 契约），
  不可携带项目自有源码；独立目录 + 构建挂载既保持 vendor 纯净，又
  复用同一构建体系。

**Alternatives**:
- 构建期脚本（Python/CMake 脚本解析 .proto）（被否：自研 IDL 解析器
  维护成本高、与 protoc 语义漂移风险、Python 依赖进入构建期）。
- 纯头文件模板/宏（URPC_SERVICE_DECLARE(...) 手写声明）（被否：
  仍是"用户手写形状"，不满足 SC-002"描述变更→编译期提醒"的自动演进；
  宏元编程可读性差）。
- 修改 vendored protobuf 源内嵌生成器（被否：违反 002 的 SHA 锚定
  契约，refetch 即丢）。

## 2. 生成物命名与符号规则

**Decision**（以 `example.EchoService`、方法 `Echo(SlowEcho 同)`、
文件 `echo.proto` 为例）:

| 生成物 | 名称 | 形态 |
|--------|------|------|
| 服务端接口 | `IEchoService` | 纯虚抽象类；每方法一个纯虚 `virtual void Echo(ServerContext&, const example_EchoRequest*, UnaryDone<example_EchoResponse>) = 0`（与现 unary.h 处理器签名同构，FR-005 上下文能力不变） |
| 未重写默认实现 | 接口内联 `{ done(Status(kUnimplemented, "..."), nullptr); }` | 业务类继承即得 UNIMPLEMENTED 兜底（FR-004） |
| 客户端代理 | `EchoServiceProxy` | `class EchoServiceProxy : public IEchoService`；构造 `EchoServiceProxy(Channel*)` / `(Client*)`；每方法提供 同步 `Result<Res> Echo(const Req*, uint64_t timeout_ms)` 与 异步 `uint64_t EchoAsync(const Req*, uint64_t, std::function<void(Result<Res>)>)` |
| 桥接 | 同文件内静态注册辅助 | `Status RegisterService(Server&, IEchoService&)`（free function，按方法表循环调用既有 RegisterUnaryFor 通道）+ 代理方法内的编码/调用/解码（复用 detail::ChannelCallRaw） |

命名推导：`I` 前缀 + PascalCase 服务名；`Proxy` 后缀；C++ 命名空间
`urpc::gen::<proto_package>`（隔离用户手写类型，Edge Case：命名冲突）。

**Rationale**: 与用户描述逐字对齐（IxxxService / XxxServiceProxy /
XxxService 继承重写）；接口签名与现存 `UnaryHandlerFn<M>` 同构使
RegisterService 能一行桥接到既有通道（内核零改动）；`urpc::gen::`
命名空间 + upb C 符号原样使用，保证两端契约同源（FR-002/007）。

**Alternatives**:
- gRPC 原版命名（`EchoService::Service` / `EchoService::Stub` 嵌套）
  （被否：用户明确要求 IXxxService/XxxServiceProxy 平铺命名）。
- 代理方法仅异步、同步由用户包装（被否：FR-006 要求双形态）。

## 3. 注册语义与生命周期

**Decision**: `Server::RegisterService<IFoo>(IFoo& impl)`（api 层
模板方法，service.h 底座提供）：
- 读取生成接口的静态方法表（`static constexpr MethodDescriptor
  kMethods[]`：方法名/路径/req-res 符号指针），逐方法经既有
  `RegisterUnaryFor` 通道注册 lambda → 转调 `impl.Xxx(ctx, req, done)`；
  非法方法重写抛出的异常由 lambda 内 try/catch 转 INTERNAL（FR-013）。
- **Server 不拥有业务实例**（引用注册；用户保证生命周期覆盖服务运行期
  ——与 gRPC 一致）；同一服务名二次注册沿用现有 Router 的拒绝行为
  （FR-003/US1-3）。
- 注册时机不限：Start 前后均可（保持 001 的动态注册语义，US1-2 不丢）。

**Rationale**: 实例整体注册 = "一次注册发布全部方法"（用户核心诉求）；
不拥有 = 与 gRPC/示例生态一致且避免 Server 析构顺序坑；复用 Router
既有重复注册拒绝 = 零新语义。

**Alternatives**:
- Server 持 shared_ptr 拥有（被否：引入生命周期隐式承诺，与 gRPC 不一致）。
- 生成 `EchoService`（非 I 前缀）的独立注册辅助类（被否：用户描述中
  XxxService 就是用户的业务类，不是生成物）。

## 4. Channel / Client / Proxy 职责三分

**Decision**:
- `Channel`（既有，client.h）：仅连接语义——target、Connect 工厂、
  关闭（析构）；跨线程可用。
- `Client`（现有 client.h 中 Channel 的别名重组）：控制面——持有
  Channel + 调用策略（首期：max_receive_message_size 等 Options 挂载，
  预留 deadline 默认值/未来重试策略位）；提供
  `EchoServiceProxy MakeProxy<EchoServiceProxy>()` 型工厂（或直接
  `template<class P> P Proxy()`）。
- 生成代理 `EchoServiceProxy`：仅业务方法；底座 `ProxyBase`
  （proxy.h）持有 `Channel*`（+可选 Client* 控制面参数），提供
  Sync/Async 模板辅助（封装 detail::ChannelCallRaw + upb 编解码，
  即现 client.h 的 CallAsync/Call 内联逻辑抽出复用）；代理无状态、
  线程安全（FR-006，沿用 001 research §3 线程模型）。
- Channel 关闭后：既有 OnConnectionLost/Stop 语义保证代理调用立即
  UNAVAILABLE（FR-009 已由现内核满足，契约测试固化）。

**Rationale**: 用户明确的三分；ProxyBase 抽公共底座让生成代码保持
极薄（只列方法转调底座），生成物稳定性最大化；Client 首期可以是
Channel 的轻包装（避免破坏性改动），控制面挂载点留演化空间（FR-010）。

**Alternatives**:
- 代理直接持有 Client 而非 Channel（被否：Channel=连接的单一事实；
  Client 是策略层，缺省可无）。
- 新建独立 Channel/Client 类层次（被否：存量 FR-014 兼容成本大，
  现有类重组职责即可满足）。

## 5. 生成物正确性验证策略（宪法 IV 落地）

**Decision** 四层：
1. **编译期**：测试 TU include 生成头并继承/实例化——签名错误即编译
   失败（SC-002 的核心机制）；static_assert 方法表与 proto 方法集
   一致。
2. **金样对照**：echo.proto 生成物快照留档 `tools/`（或 test 内联
   关键片段断言），生成器输出漂移使测试失败。
3. **行为端到端**：test_typed_e2e.cpp——接口实现服务端 + 代理客户端
   走真实 loopback，覆盖 US1/US2 全部验收场景（含 UNIMPLEMENTED 兜底、
   重复注册拒绝、取消感知、并发、deadline）。
4. **回归**：examples 迁移后 examples-echo-e2e、全量 ctest、gRPC
   Python 互操作保持全绿（FR-012）；基准门禁延续（性能目标）。

**Rationale**: 生成器的"行为"就是生成文本，编译+金样是最高效的等价
性证明；行为语义仍由运行时测试背书，分层无死角。

**Alternatives**:
- 仅行为测试不金样（被否：生成物回归无哨兵，SC-002 不可判定）。
- 金样放 specs/（被否：specs 是规格工件；tools/ 是工程留档惯例）。

## 6. grpc-timeout 传播（代理携带 deadline）

**Decision**: 代理方法的 `timeout_ms` 参数经既有 Channel::Call 的
timeout 通道传播（客户端 timer + `grpc-timeout` header——001 已实现
服务端解析与 OnDeadline）；生成代理不在接口签名中引入新概念，
`timeout_ms=0` 沿用"不超时"语义。

**Rationale**: 线协议行为完全复用（FR-012）；接口面零新增概念，
与存量 Channel::Call 参数对齐。

**Alternatives**: std::chrono 类型化 deadline（被否：接口签名引入
chrono 依赖，且与现 API 风格不一致；留待接口整体演进时再议）。
