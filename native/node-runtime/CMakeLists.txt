# CMakeLists.txt for libcapacitor_node.so
#
# Builds the NAPI module that embeds the prebuilt libnode.so from
# https://github.com/electerm/ohos-node-shared. libnode.so is NOT linked here:
# linking it would record DT_NEEDED "libnode.so.137" (its SONAME) while the
# file shipped in the HAP is named "libnode.so", and the OHOS linker resolves
# DT_NEEDED by exact filename — the module would then fail to load. Instead
# node_embed.cpp dlopen()s it at runtime (same dir as this module / linker
# namespace search), which is exactly how electerm-harmony consumes it.
#
# Sources:
#   capacitor_node.cpp  OHOS NAPI addon (uses only the OHOS sysroot headers)
#   node_embed.cpp      embedded Node launcher (pure libc + dlopen/dlsym —
#                       includes neither NAPI nor Node headers)
#
# Inputs consumed at RUNTIME (not build time):
#   entry/libs/<abi>/libnode.so  downloaded by scripts/prepare-node.sh and
#                                packaged into the HAP by hvigor
#
# The two translation units used to live in separate targets because they
# needed disjoint NAPI header sets (OHOS vs Node's own). node_embed.cpp no
# longer includes any NAPI/Node headers, so a single shared library is enough
# — which also stops hvigor from packing a stray libnode_embed.a into the HAP.

cmake_minimum_required(VERSION 3.16.0)
project(capacitor_node)

set(OHOS_ARCH "$ENV{OHOS_ARCH}" CACHE STRING "target ABI")
if(NOT OHOS_ARCH)
  set(OHOS_ARCH "arm64-v8a")
endif()

add_definitions(-DLOG_DOMAIN=0x0000)
add_definitions(-DLOG_TAG="capacitor_node")

add_library(capacitor_node SHARED
  capacitor_node.cpp
  node_embed.cpp
)
target_include_directories(capacitor_node PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_options(capacitor_node PRIVATE
  -std=c++20
  -fexceptions
  -frtti
  -fno-emulated-tls
  -Wall
  -Wno-unused-parameter
)

# Only OHOS system libraries: libnode.so is dlopen'd at runtime, never linked.
target_link_libraries(capacitor_node
  PUBLIC
  libace_napi.z.so
  libhilog_ndk.z.so
  libc++.so
)
