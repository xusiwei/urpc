# Contract: Wire Protocol（gRPC 一元线协议映射）

本特性对外遵守 gRPC over HTTP/2 的一元调用语义（宪法原则 I）。以下为
框架内核必须实现的线上行为契约；实现于 `libs/core`（nghttp2 会话）。

## 请求（客户端 → 服务端）

| 元素 | 值 / 规则 |
|------|-----------|
| `:method` | POST |
| `:scheme` | http（本特性明文） |
| `:path` | `/服务全名/方法名`（与注册路由键一致） |
| `:authority` | 目标地址 |
| `content-type` | `application/grpc`（+proto 后缀容忍 `application/grpc+proto`） |
| `te` | `trailers` |
| `grpc-timeout` | 存在截止时间时携带；格式 `Sm/Sn`（值+单位，最大小时） |
| DATA | 恰好一条消息：5 字节前缀（1 字节压缩标志=0 + 4 字节大端长度）+ protobuf 编码；END_STREAM 随最后 DATA 或空 DATA 帧 |

不兼容的 content-type / 调用形态 → 标准状态码拒绝（spec 边界情形）。

## 响应（服务端 → 客户端）

| 元素 | 值 / 规则 |
|------|-----------|
| 响应头 | `:status 200`；正常路径不提前下发 `grpc-status` |
| DATA | 恰好一条消息（同上 5 字节前缀编码；允许零长度消息） |
| Trailers | `grpc-status`（十进制状态码，必填）+ `grpc-message`（可选，百分号编码文本） |
| 失败可先行 | 逻辑错误（UNIMPLEMENTED/INTERNAL/…）可仅以 trailers 终结，无 DATA |

## 状态码映射（闭合集合，FR-003）

| 场景 | grpc-status |
|------|-------------|
| 成功 | 0 (OK) |
| 路由键不存在 | 12 (UNIMPLEMENTED) |
| 处理器失败/迟到写响应 | 13 (INTERNAL) |
| 截止时间到（双向） | 4 (DEADLINE_EXCEEDED) |
| 消息超上限 | 8 (RESOURCE_EXHAUSTED) |
| 通道断开/强制关闭阶段 | 14 (UNAVAILABLE) |
| 解码失败 | 15 (DATA_LOSS) |

## 取消与关闭

- 客户端主动取消：RST_STREAM（CANCEL）或 END_STREAM 前断开；服务端
  触发处理器取消回调并释放流资源（不悬挂）。
- 截止时间：双端各自执行定时器；服务端先到 → 取消通知 + 4；
  客户端先到 → 本地 4 + 取消在途流。
- 优雅关闭：GOAWAY（含最后可接受流 ID）→ 等待/宽限 → 强制（客户端
  观感 UNAVAILABLE）。

## 大小与流控

- 接收侧消息重组缓冲以 `max_receive_message_size` 为界（默认 4MiB，
  分端可配）；超限按上表终止该调用，连接保持。
- HTTP/2 流控采用 nghttp2 默认数据窗（本特性不做调优，基准仅记录）。
