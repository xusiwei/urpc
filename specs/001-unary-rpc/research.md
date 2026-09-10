# Phase 0 Research: Unary Request/Response

本文件记录将规格未知项转为实现决策的研究结论。格式：决策 → 理由 →
备选方案。

## 1. 性能目标与回归阈值（规格遗留：绝对数值在计划阶段定案）

**Decision**（回环环境、1KiB protobuf 消息、单进程双端同机）：

- 串行一元调用往返时延（p50/p99）：≤ 300µs / ≤ 1.5ms
- 单连接并发（4 在途）吞吐：≥ 10,000 ops/s
- 回归门禁：与留档基线同环境对比，中位指标退化 > 10% 阻断合入；
  基线结果以机器可读格式（JSON）留档于 `tools/` 约定目录

**Rationale**: 参照官方 gRPC C++ 在回环环境的公开量级（数百 µs 级
RTT），为用户态 HTTP/2 + protobuf 栈留出 1.5–2× 余量；相对门禁
（>10% 退化）消除机器间差异，使跨平台 CI 可执行。

**Alternatives**: 相对官方 gRPC 同机倍率目标（被否：基准依赖引入完整
gRPC，违反依赖边界）；不定数值仅留基线（被否：无法阻断回退，SC-003
不可判定）。

## 2. 依赖引入与版本固定

**Decision**: 顶层 CMake 统一封装 `urpc::` 依赖宏（优先
`find_package`，缺失则 FetchContent 固定 tag）：
libuv ≥1.46、nghttp2 ≥1.62、protobuf（upb 子集）固定实现期最新
stable tag、GoogleTest ≥1.14、benchmark ≥1.8（后两者仅测试构建）。
版本号集中声明于一处（`cmake/urpc-deps.cmake`），升级需过全部门禁。

**Rationale**: 单点固定满足宪法原则 V「版本固定并经评审」；系统包
优先满足可嵌入场景（发行版分发）。

**Alternatives**: git submodule（被否：Windows 体验差，已讨论）；
vcpkg/Conan（被否：额外工具链，超出宪法依赖边界）。

## 3. 线程与事件循环模型

**Decision**: 每个运行实体（Server / Channel）内含专属事件循环线程；
外部线程经线程安全入口（内部无锁队列 + `uv_async_send` 唤醒）投递
调用；客户端代理对象仅持有不可变连接信息 + 线程安全句柄，任意线程
可并发使用。同步调用 = 异步调用 + 等待原语，入口处检测「当前线程
是否为框架事件循环线程」，是则立即返回明确错误（快速失败，对应
Clarifications 第 5 条）。

**Rationale**: libuv 单线程循环避免内核内锁；代理对象线程安全直接
落实 FR-005；自锁死风险在入口处以最低成本消除。

**Alternatives**: 多线程共享循环 + 细粒度锁（被否：nghttp2 会话非
线程安全，锁竞争伤害时延）；同步接口嵌套驱动循环（被否：重入复杂，
已由用户否决）。

## 4. 服务端处理器形态与取消传播

**Decision**: 处理器签名为回调形式：
`(ServerContext&, const RequestMsg&, HandlerCompletion&&)`；
`ServerContext` 携带截止时间视图与取消状态（可注册取消回调）。
截止时间到达时框架：① 置取消态并触发处理器注册的回调；② 停止接收
该流后续数据；③ 若处理器已完成写出则按已写结果收尾，否则以
DEADLINE_EXCEEDED 结束流并告知客户端。处理器提前终止后不得再写响应
（写入返回错误）。

**Rationale**: gRPC 语义对齐（Clarifications 第 1 条、FR-004）；
回调式取消避免强制业务线程化。

**Alternatives**: 强制处理器运行于独立线程池（被否：线程策略应留给
用户层/后续特性）；轮询取消标志（被否：时延与语义均差）。

## 5. 优雅关闭

**Decision**: `Server::Shutdown(grace)`：① 停止接受新连接与新调用
（发 GOAWAY，MAX_CONCURRENT 遗留流上限递减）；② 等待在途调用完成
至宽限期耗尽；③ 强制取消剩余调用（客户端收到 UNAVAILABLE），释放
全部资源，循环线程退出。

**Rationale**: 对应 Clarifications 第 6 条与 FR-012；GOAWAY 是 HTTP/2
标准做法，官方客户端可感知排空。

**Alternatives**: 立即关闭（被否：用户已否决）；无限等待（被否：
不可用于生产守护进程退出）。

## 6. 最小日志（自研）

**Decision**: core 内自研轻量结构化日志：级别（error/warn/info/debug）
+ 类别（conn/call）+ 关键事件（连接建立/关闭、调用开始/结束与状态码）；
输出目标可注入（默认 stderr）；同步接口形态（无后台线程、无锁队列），
生产默认级别 warn，基准/测试可调。

**Rationale**: FR-011 最小内建；宪法原则 V 固定依赖集合 → 不引
spdlog 等第三方；同步简单实现满足排查刚需且零隐藏线程。

**Alternatives**: 引入 spdlog（被否：违宪新增依赖）；完全无日志
（被否：Clarifications 第 2 条已定最小内建）。

## 7. 消息编解码与大小上限

**Decision**: 请求/响应消息以 upb 消息指针为核心表示；api 层暴露
强类型 stub 模板（基于 proto 生成的 upb C API）；接收上限默认 4MiB
（Server/Channel 可配置），超限以 RESOURCE_EXHAUSTED 终止该调用、
连接保持可用。proto → upb C 代码生成经 protobuf 源内
`protoc --upb_out`（FetchContent 的 protobuf 已含）。

**Rationale**: upb 轻量、C 接口天然贴合 C-ABI 边界（原则 II）；
上限默认对齐 gRPC 社区默认（FR-007）。

**Alternatives**: 完整 protobuf C++ 库（被否：重、异常语义越界，
且宪法技术栈既定为 upb）。

## 8. 互通验收工具链

**Decision**: `interop/` 内共享一份 proto；gRPC Python
（grpcio/grpcio-tools）脚本 `interop/python/peer_client.py` 与
`peer_server.py`；ctest 驱动四象限：官方客户端×urpc 服务端、
urpc 客户端×官方服务端，各覆盖成功与错误（UNIMPLEMENTED、
DEADLINE_EXCEEDED）场景。Python 依赖以 requirements.txt 固定，
CI 中可选启用（本机必过）。

**Rationale**: 对应 Clarifications 第 3 条与 SC-004；脚本小、官方
实现权威、无反射需求。

**Alternatives**: grpcurl（被否：需服务端反射，扩 scope）；
官方 interop suite（被否：覆盖远超本特性，重量级）。

## 9. CMake 工程组织

**Decision**: 顶层 `CMakeLists.txt` 定义项目与全局选项（
`URPC_BUILD_TESTS/URPC_BUILD_BENCH/URPC_BUILD_EXAMPLES`、
`URPC_WERROR`），FetchContent 于 `cmake/urpc-deps.cmake`；
`libs/{core,cabi,api}` 各为独立目标，以
`target_include_directories(... PRIVATE)` + usage requirements
强制可见性；`CMakePresets.json` 提供 debug/release × 三平台预设；
统一 `urpc-*` 目标命名。最低版本 CMake 3.21。

**Rationale**: 编译期分层强制（方案 A 定稿）；presets 跨平台一致
体验（原则 III）。

**Alternatives**: 单一超级目标（被否：分层退化为约定）。

## 10. 端到端示例形态

**Decision**: `examples/echo/`：一个服务端进程（注册 Echo 方法）+
一个客户端进程（循环调用并校验回显），退出码表达成败；ctest 以
超时保护运行；同一示例同时是 SC-001 的「30 分钟上手」载体
（quickstart.md 指引复刻）。

**Rationale**: FR-008/US3；进程级闭环避免测试桩与真实栈漂移。

**Alternatives**: 单进程内自连（被否：绕过真实网络路径，削弱端到端
意义）。
