#pragma once

#include <functional>
#include <memory>
#include <string>

#include <cstdio>
#include <cstdlib>
#include <future>

#include <upb/mem/arena.h>
#include <upb/message/message.h>
#include <upb/wire/encode.h>


#include "urpc/core/status.h"
#include "urpc/core/codec.h"
#include "urpc/detail/raw.h"

namespace urpc {

// Public alias: the canonical Status type (urpc::core::Status).
using Status = ::urpc::core::Status;
using StatusCode = ::urpc::core::StatusCode;

// Response of a unary call: status + typed payload (arena-backed; the
// message stays valid as long as the Result holds it).
template <typename Res>
class Result {
 public:
  Result() = default;
  Result(::urpc::Status status, std::shared_ptr<const Res> value)
      : status_(std::move(status)), value_(std::move(value)) {}

  bool ok() const { return status_.ok() && value_ != nullptr; }
  const ::urpc::Status& status() const { return status_; }
  const Res* value() const { return value_.get(); }

 private:
  ::urpc::Status status_;
  std::shared_ptr<const Res> value_;
};

class Channel {
 public:
  struct Options {
    std::string target = "127.0.0.1:50051";
    size_t max_receive_message_size = 4u * 1024 * 1024;
  };

  // Lazy connection: the first call triggers the dial. Never fails.
  static std::shared_ptr<Channel> Connect(const std::string& target);

  void set_max_receive_message_size(size_t n);

  // --- typed unary calls (M = URPC_UNARY_METHOD traits from unary.h) --------
  // Async (primary form; any thread): callback fires exactly once.
  template <typename M>
  uint64_t CallAsync(const std::string& service, const std::string& method,
                     const typename M::ReqType* request, uint64_t timeout_ms,
                     std::function<void(Result<typename M::ResType>)> done) {
    upb_Arena* arena = upb_Arena_New();
    if (arena == nullptr) {
      Fail(done, Status(StatusCode::kInternal, "arena alloc failed"));
      return 0;
    }
    char* buf = nullptr;
    size_t n = 0;
    upb_EncodeStatus es =
        upb_Encode(reinterpret_cast<const upb_Message*>(request), M::ReqTable(),
                   0, arena, &buf, &n);
    if (es != kUpb_EncodeStatus_Ok) {
      upb_Arena_Free(arena);
      Fail(done, Status(StatusCode::kInternal, "request encode failed"));
      return 0;
    }
    std::string framed;
    urpc::core::EncodeFrame(std::string(buf, n), &framed);
    upb_Arena_Free(arena);

    const std::string path = "/" + service + "/" + method;
    return detail::ChannelCallRaw(
        this, path, framed, timeout_ms,
        [done = std::move(done)](Status st, std::string payload) {
          if (getenv("URPC_WIRE_DEBUG")) {
            std::fprintf(stderr, "[api] resp payload(%zu):", payload.size());
            for (size_t i = 0; i < payload.size(); i++)
              std::fprintf(stderr, " %02x", (unsigned char)payload[i]);
            std::fprintf(stderr, "\n");
          }
          if (!st.ok()) {
            done(Result<typename M::ResType>(st, nullptr));
            return;
          }
          upb_Arena* ra = upb_Arena_New();
          if (ra == nullptr) {
            done(Result<typename M::ResType>(
                Status(StatusCode::kInternal, "arena alloc failed"), nullptr));
            return;
          }
          auto* res = M::ParseResponse(payload.data(), payload.size(), ra);
          if (res == nullptr) {
            upb_Arena_Free(ra);
            done(Result<typename M::ResType>(
                Status(StatusCode::kDataLoss, "response decode failed"),
                nullptr));
            return;
          }
          std::shared_ptr<const typename M::ResType> holder(
              res, [ra](const typename M::ResType*) { upb_Arena_Free(ra); });
          done(Result<typename M::ResType>(st, std::move(holder)));
        });
  }

  // Sync convenience form. MUST NOT be used on a urpc event-loop thread:
  // fast-fails with an INTERNAL status instead of deadlocking (FR-002).
  template <typename M>
  Result<typename M::ResType> Call(const std::string& service,
                                   const std::string& method,
                                   const typename M::ReqType* request,
                                   uint64_t timeout_ms) {
    if (detail::ChannelOnLoopThread(this)) {
      return Result<typename M::ResType>(
          Status(StatusCode::kInternal,
                 "sync Call() is not allowed on the urpc event-loop thread"),
          nullptr);
    }
    std::promise<Result<typename M::ResType>> p;
    auto fut = p.get_future();
    CallAsync<M>(service, method, request, timeout_ms,
                 [&p](Result<typename M::ResType> r) {
                   p.set_value(std::move(r));
                 });
    return fut.get();
  }

  Channel();
  ~Channel();
  Channel(const Channel&) = delete;
  Channel& operator=(const Channel&) = delete;

  class Impl;
  Impl* impl() const { return impl_.get(); }  // internal: detail bridge

 private:
  template <typename Res>
  static void Fail(std::function<void(Result<Res>)>& done, Status st) {
    if (done) done(Result<Res>(std::move(st), nullptr));
  }

  std::unique_ptr<Impl> impl_;
};

}  // namespace urpc
