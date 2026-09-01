# Top-level CMake for the entry module's native build.
#
# Routes the embedded-Node runtime (copied from capacitor-harmony's
# native/node-runtime) below.  Argument/env vars are honoured by the subdir's
# CMakeLists — see native/node-runtime/CMakeLists.txt.

cmake_minimum_required(VERSION 3.16.0)
project(capacitor_cpp)

add_subdirectory(capacitor_node)
