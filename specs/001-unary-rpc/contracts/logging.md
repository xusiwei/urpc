# Contract: Logging（最小可观测接口）

FR-011 的接口契约；实现于 `libs/core`（自研，research.md §6），
api 层透出配置入口。

## 级别与类别

```cpp
enum class LogLevel { kError, kWarn, kInfo, kDebug };  // 生产默认 kWarn

enum class LogCategory { kConnection, kCall };          // conn / call
```

## 事件集合（闭合）

| 类别 | 事件 | 级别 | 字段 |
|------|------|------|------|
| conn | 连接建立 | info | 本端/对端地址、方向（server/client） |
| conn | 连接关闭 | info | 对端地址、原因（正常/错误码）、存活时长 |
| call | 调用开始 | info | 路径、流 ID、截止时间（有无） |
| call | 调用结束 | info | 路径、流 ID、grpc-status、耗时（µs） |
| conn/call | 异常路径（解码失败、超限、迟到写响应等） | warn/error | 同上 + 原因 |

## 配置接口（api 层）

```cpp
LoggingOptions options;
options.set_level(LogLevel::kInfo);                       // 级别门控
options.set_sink(/* 自定义输出目标，默认 stderr */);
ServerBuilder::set_logging(options);                      // 分端配置
ChannelOptions::set_logging(options);
```

## 契约要点

| 契约 | 对应 |
|------|------|
| 结构化输出：级别+类别+事件+字段（键值），单行一条 | FR-011「结构化」 |
| 级别可配置且默认生产友好（warn） | FR-011「级别 MUST 可控制」 |
| 无指标、无追踪（明确排除） | Clarifications #2 |
| 日志调用为同步形态，不引入后台线程/第三方依赖 | 原则 V、research.md §6 |
| 事件集合闭合：上表之外的内部细节不得进入公共日志输出 | 最小内建约定 |
