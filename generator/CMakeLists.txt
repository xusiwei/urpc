# protoc-gen-urpc — service interface/proxy generator plugin (spec 003).
#
# Built against the vendored protobuf toolchain (same plugin mechanism as
# protoc-gen-upb; see urpc-deps.cmake for the add_subdirectory hookup).
# Standard CMake entry; zero new external dependencies (constitution V).

add_executable(protoc-gen-urpc urpc_codegen.cc)
target_link_libraries(protoc-gen-urpc PRIVATE libprotoc libprotobuf)
target_compile_features(protoc-gen-urpc PRIVATE cxx_std_17)
