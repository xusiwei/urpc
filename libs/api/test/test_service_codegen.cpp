// Generated-service contract tests (spec 003, T009 / research.md §5).
//
// Layer 1 (compile-time): including "echo.service.h" and instantiating the
// interface/proxy already proves the generated signatures exist.
// Layer 2 (gold-sample): the generated header must contain the contractual
// fragments (interface, proxy inheritance, registration helper, method
// table, UNIMPLEMENTED defaults).

#include <cstdio>
#include <fstream>
#include <string>

#include "echo.service.h"
#include "echo.upb.h"

#include <gtest/gtest.h>

namespace {

using urpc::gen::example::EchoServiceProxy;
using urpc::gen::example::IEchoService;

// Instantiating an implementation proves the interface is concrete (all
// methods have defaults) and the vtable layout exists.
class CodegenFixtureImpl : public IEchoService {};

TEST(ServiceCodegen, InterfaceIsInstantiableAndMethodTableComplete) {
  static_assert(std::size(IEchoService::kMethods) == 2,
                "echo.proto declares exactly two methods");
  CodegenFixtureImpl impl;
  (void)impl;
  SUCCEED();
}

// Gold-sample: the generated header text contains the contractual
// fragments. Tolerates host-side file encryption (DLP) by skipping when
// the content cannot be read as text.
TEST(ServiceCodegen, GeneratedHeaderContainsContractFragments) {
  const char* path = URPC_ECHO_SERVICE_HEADER;
  std::ifstream in(path, std::ios::binary);
  if (!in.good()) {
    GTEST_SKIP() << "generated header not readable at: " << path;
  }
  std::string content((std::istreambuf_iterator<char>(in)),
                      std::istreambuf_iterator<char>());
  if (content.find("Esafenet") != std::string::npos ||
      content.find_first_of("\x00\x01\x02", 0, 1) != std::string::npos) {
    GTEST_SKIP() << "generated header unreadable (host file encryption)";
  }

  // Interface + proxy inheritance (FR-001/002).
  EXPECT_NE(content.find("class IEchoService"), std::string::npos);
  EXPECT_NE(content.find("class EchoServiceProxy : public IEchoService"),
            std::string::npos);
  // Registration helper (FR-003).
  EXPECT_NE(content.find("RegisterService(::urpc::Server& server"),
            std::string::npos);
  // Method table (declaration order preserved).
  EXPECT_NE(content.find("\"Echo\", \"/example.EchoService/Echo\""),
            std::string::npos);
  EXPECT_NE(content.find("\"SlowEcho\", \"/example.EchoService/SlowEcho\""),
            std::string::npos);
  // UNIMPLEMENTED defaults (FR-004).
  EXPECT_NE(content.find("kUnimplemented"), std::string::npos);
}

}  // namespace
