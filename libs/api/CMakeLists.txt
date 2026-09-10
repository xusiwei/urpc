add_library(urpc_api
  source/version.cpp
)

target_include_directories(urpc_api PUBLIC include)
target_link_libraries(urpc_api PRIVATE urpc_cabi)

if(BUILD_TESTING AND URPC_BUILD_TESTS)
  file(GLOB URPC_API_TESTS test/test_*.cpp)
  if(URPC_API_TESTS)
    add_executable(urpc_api_tests ${URPC_API_TESTS})
    target_link_libraries(urpc_api_tests PRIVATE urpc_api GTest::gtest GTest::gtest_main)
    add_test(NAME urpc-api COMMAND urpc_api_tests)
  endif()
endif()
