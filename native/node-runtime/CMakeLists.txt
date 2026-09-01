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

include_directories(
  ${NODE_INCLUDE_DIR}
  ${NODE_INCLUDE_DIR}/node
  ${CMAKE_CURRENT_SOURCE_DIR}
)

add_library(capacitor_node SHARED
  capacitor_node.cpp
)

target_link_libraries(capacitor_node
  PUBLIC
  ${NODE_LIB_DIR}/libnode.so
  libace_napi.z.so
  libuv.so
  libc++.so
  libz.so
  libhilog_ndk.z.so
)

target_compile_options(capacitor_node PUBLIC
  -std=c++20
  -fexceptions
  -frtti
  -fno-emulated-tls
  -Wall
  -Wno-unused-parameter
)

target_compile_definitions(capacitor_node PUBLIC NODE_API_WITH_INIT=1)
