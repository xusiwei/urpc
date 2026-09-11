#pragma once

#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "urpc/core/status.h"

namespace urpc {
namespace core {

// Per-call context handed to core unary handlers (untyped: bytes in/out;
// typed wrapping lives in libs/api on top of upb generated code).
class ServerCallCtx {
 public:
  virtual ~ServerCallCtx() = default;

  // Completes the call exactly once. Subsequent calls return an error
  // Status (late writes are rejected, spec edge case).
  virtual Status Respond(Status status, const std::string& payload) = 0;

  virtual bool IsCancelled() const = 0;
  // Registers a cancellation callback (deadline, client cancel, forced
  // shutdown). Returns false when already cancelled.
  virtual bool OnCancel(std::function<void()> cb) = 0;
  // Remaining time in ms; 0 when no deadline is set or it has expired.
  virtual uint64_t TimeRemainingMs() const = 0;

  virtual const std::string& path() const = 0;
};

using UnaryHandler =
    std::function<void(ServerCallCtx&, const std::string& request)>;

// Path ("/<service>/<method>") → handler registry with copy-on-write
// snapshots so the read path is lock-free (data-model.md: Router).
class Router {
 public:
  Status RegisterUnary(const std::string& path, UnaryHandler handler);
  std::optional<UnaryHandler> Find(const std::string& path) const;

  size_t size() const;

 private:
  mutable std::mutex mu_;
  std::shared_ptr<const std::map<std::string, UnaryHandler>> snapshot_ =
      std::make_shared<const std::map<std::string, UnaryHandler>>();
};

}  // namespace core
}  // namespace urpc
