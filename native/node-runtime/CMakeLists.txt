# CMakeLists.txt for libcapacitor_node.so
#
# Builds the small NAPI module that embeds the prebuilt shared libnode.so.
# Two inputs must be provided (see scripts/prepare-headers.sh and
# scripts/prepare-node.sh, which are run automatically by build-hap.sh):
#
#   NODE_INCLUDE_DIR  directory with Node.js v24.2.0 headers (node.h, v8.h,
#                      libplatform.h, uv.h, ...)
#   NODE_LIB_DIR      directory containing libnode.so for the target ABI
#
# Both default to locations relative to the HAP root so a plain `build-hap.sh`
# works out of the box once the two prepare steps have run.
#
# IMPORTANT — NAPI header isolation
# ---------------------------------
# The two translation units pull in two INCOMPATIBLE napi header sets:
#   * capacitor_node.cpp  -> OHOS NAPI (napi/native_api.h from the OHOS sysroot)
#   * node_embed.cpp      -> Node's own NAPI shim (node.h / js_native_api.h)
# Both declare the same `napi_*` symbols, but with a different `env` type
# (OHOS: `napi_env`; Node: `node_api_basic_env`). If Node's headers end up on
# the include path of capacitor_node.cpp, OHOS native_api.h transitively
# includes Node's js_native_api.h and the symbols clash ("conflicting types").
# Therefore Node's headers are exposed ONLY to node_embed.cpp (via its own
# target_include_directories). capacitor_node.cpp relies solely on the OHOS
# sysroot headers, so its own js_native_api.h is resolved correctly.

cmake_minimum_required(VERSION 3.16.0)
project(capacitor_node)

set(OHOS_ARCH "$ENV{OHOS_ARCH}" CACHE STRING "target ABI")
if(NOT OHOS_ARCH)
  set(OHOS_ARCH "arm64-v8a")
endif()

set(NODE_INCLUDE_DIR "$ENV{NODE_INCLUDE_DIR}" CACHE PATH "Node.js headers")
if(NOT NODE_INCLUDE_DIR)
  set(NODE_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../node-headers/include")
endif()

set(NODE_LIB_DIR "$ENV{NODE_LIB_DIR}" CACHE PATH "directory with libnode.so")
if(NOT NODE_LIB_DIR)
  set(NODE_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../libs/${OHOS_ARCH}")
endif()

add_definitions(-DLOG_DOMAIN=0x0000)
add_definitions(-DLOG_TAG="capacitor_node")

# ---------------------------------------------------------------------------
# node_embed — embedded Node runtime. Node headers are visible ONLY here.
# ---------------------------------------------------------------------------
add_library(node_embed STATIC node_embed.cpp)
target_include_directories(node_embed PRIVATE
  ${NODE_INCLUDE_DIR}
  ${NODE_INCLUDE_DIR}/node
  ${CMAKE_CURRENT_SOURCE_DIR}
)
target_compile_definitions(node_embed PRIVATE NODE_API_WITH_INIT=1)
target_compile_options(node_embed PRIVATE
  -std=c++20
  -fexceptions
  -frtti
  -fno-emulated-tls
  -Wall
  -Wno-unused-parameter
)

# ---------------------------------------------------------------------------
# capacitor_node — OHOS NAPI addon driving node_embed. Only the OHOS NAPI
# headers (from the OHOS sysroot) are visible, so it never sees Node's napi.
# ---------------------------------------------------------------------------
add_library(capacitor_node SHARED capacitor_node.cpp)
target_include_directories(capacitor_node PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(capacitor_node PRIVATE NODE_API_WITH_INIT=1)
target_compile_options(capacitor_node PRIVATE
  -std=c++20
  -fexceptions
  -frtti
  -fno-emulated-tls
  -Wall
  -Wno-unused-parameter
)

target_link_libraries(capacitor_node
  PUBLIC
  node_embed
  ${NODE_LIB_DIR}/libnode.so
  libace_napi.z.so
  libuv.so
  libc++.so
  libz.so
  libhilog_ndk.z.so
)
