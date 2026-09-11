#include "urpc/core/router.h"

namespace urpc {
namespace core {

Status Router::RegisterUnary(const std::string& path, UnaryHandler handler) {
  if (path.empty() || path.front() != '/' || handler == nullptr) {
    return Status(StatusCode::kInternal, "invalid registration: " + path);
  }
  std::lock_guard<std::mutex> lock(mu_);
  auto next = std::make_shared<std::map<std::string, UnaryHandler>>(
      *snapshot_);
  if (next->count(path) != 0) {
    return Status(StatusCode::kInternal,
                  "duplicate method path: " + path + " (rejected)");
  }
  (*next)[path] = std::move(handler);
  snapshot_ = std::move(next);  // atomic snapshot swap (readers lock-free)
  return Status::Ok();
}

std::optional<UnaryHandler> Router::Find(const std::string& path) const {
  std::shared_ptr<const std::map<std::string, UnaryHandler>> snap;
  {
    std::lock_guard<std::mutex> lock(mu_);
    snap = snapshot_;
  }
  auto it = snap->find(path);
  if (it == snap->end()) return std::nullopt;
  return it->second;
}

size_t Router::size() const {
  std::shared_ptr<const std::map<std::string, UnaryHandler>> snap;
  {
    std::lock_guard<std::mutex> lock(mu_);
    snap = snapshot_;
  }
  return snap->size();
}

}  // namespace core
}  // namespace urpc
