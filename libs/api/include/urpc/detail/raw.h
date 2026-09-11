#pragma once

// Internal bridge between the header-inline typed API templates and the
// hidden implementation (urpc_api_impl.cpp). Not part of the public surface.

#include <functional>
#include <string>

#include "urpc/core/status.h"
#include "urpc/server.h"

namespace urpc {

class Channel;

namespace detail {

using RawDone = std::function<void(::urpc::Status, const std::string&)>;

// Server: registers a bytes-level unary handler under "/service/method".
::urpc::Status RegisterUnaryRaw(
    Server* server, const std::string& service, const std::string& method,
    std::function<void(ServerContext&, const std::string& request, RawDone)>
        raw_handler);

// Channel: framed async unary call. done fires exactly once.
uint64_t ChannelCallRaw(Channel* channel, const std::string& path,
                        const std::string& framed_request, uint64_t timeout_ms,
                        std::function<void(::urpc::Status, std::string)> done);

// True when the caller is on a urpc event-loop thread (sync calls must
// fast-fail there — FR-002).
bool ChannelOnLoopThread(Channel* channel);

}  // namespace detail
}  // namespace urpc
