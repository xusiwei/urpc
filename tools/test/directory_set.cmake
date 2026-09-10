# directory_set.cmake — guard: third_party/ contains exactly the vendored C++
# dependencies (+ manifest + README) and no Python artifacts (FR-007 / US4).

cmake_minimum_required(VERSION 3.21)

get_filename_component(URPC_REPO "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(URPC_TP "${URPC_REPO}/third_party")

set(URPC_ALLOWED libuv nghttp2 protobuf abseil googletest benchmark versions.cmake README.md)

file(GLOB URPC_ENTRIES RELATIVE "${URPC_TP}" "${URPC_TP}/*")

set(URPC_ERR "")
foreach(e IN LISTS URPC_ENTRIES)
  list(FIND URPC_ALLOWED "${e}" idx)
  if(idx EQUAL -1)
    string(APPEND URPC_ERR "unexpected entry 'third_party/${e}'; ")
  endif()
endforeach()
foreach(req IN LISTS URPC_ALLOWED)
  if(NOT EXISTS "${URPC_TP}/${req}")
    string(APPEND URPC_ERR "missing expected entry 'third_party/${req}'; ")
  endif()
endforeach()

# no Python artifacts anywhere under third_party/
file(GLOB_RECURSE URPC_PY_ARTIFACTS
  "${URPC_TP}/*.pyc"
  "${URPC_TP}/*.egg-info"
  "${URPC_TP}/*.whl"
  "${URPC_TP}/site-packages")
if(URPC_PY_ARTIFACTS)
  string(APPEND URPC_ERR "python artifacts present: ${URPC_PY_ARTIFACTS}; ")
endif()

if(URPC_ERR STREQUAL "")
  message(STATUS "directory_set: PASS (third_party/ holds exactly the six C++ deps + manifest + README)")
else()
  message(FATAL_ERROR "directory_set: FAIL — ${URPC_ERR}")
endif()
