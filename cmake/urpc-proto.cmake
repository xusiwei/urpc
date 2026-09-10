# urpc-proto.cmake — proto → upb C code generation.
#
# Uses the host protoc (URPC_PROTOC_EXECUTABLE, see urpc-deps.cmake) with the
# built-in --upb_out generator. Generated code pairs with the urpc_upb runtime.

function(urpc_proto_upb)
  cmake_parse_arguments(ARG "" "PROTO;OUT_DIR;IMPORT_DIR" "TARGETS" ${ARGN})
  if(NOT ARG_PROTO)
    message(FATAL_ERROR "urpc_proto_upb: PROTO is required")
  endif()
  if(NOT ARG_OUT_DIR)
    message(FATAL_ERROR "urpc_proto_upb: OUT_DIR is required")
  endif()

  get_filename_component(proto_abs "${ARG_PROTO}" ABSOLUTE)
  get_filename_component(proto_name_we "${proto_abs}" NAME_WE)
  set(gen_h "${ARG_OUT_DIR}/${proto_name_we}.upb.h")
  set(gen_c "${ARG_OUT_DIR}/${proto_name_we}.upb.c")

  add_custom_command(OUTPUT "${gen_h}" "${gen_c}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${ARG_OUT_DIR}"
    COMMAND "${URPC_PROTOC_EXECUTABLE}"
            "--proto_path=${ARG_IMPORT_DIR}"
            "--upb_out=${ARG_OUT_DIR}"
            "${proto_abs}"
    DEPENDS "${proto_abs}" ${URPC_PROTOC_TARGET}
    COMMENT "urpc: upb codegen ${proto_name_we}.proto"
    VERBATIM)

  if(ARG_TARGETS)
    foreach(t IN LISTS ARG_TARGETS)
      target_sources(${t} PRIVATE "${gen_c}")
      target_include_directories(${t} PUBLIC "${ARG_OUT_DIR}")
    endforeach()
  endif()
endfunction()
