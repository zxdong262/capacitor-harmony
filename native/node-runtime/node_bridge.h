// node_bridge.h — C ABI bridging the OHOS NAPI addon (capacitor_node.cpp)
// and the embedded Node runtime (node_embed.cpp).
//
// The two translation units intentionally include disjoint NAPI headers
// (OHOS NAPI vs Node's own NAPI, which use a different `env` type name and
// therefore clash if mixed in one TU). They communicate only through these
// plain C function pointers, so neither side needs the other's NAPI headers.

#pragma once

#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

// A line emitted by the embedded Node process.
//   level : "stdout" or "stderr"
//   line  : UTF-8 text without a trailing newline
typedef void (*cap_output_cb)(const char* level, const char* line);

// Called exactly once when the embedded Node process exits.
//   code : process exit code
typedef void (*cap_exit_cb)(int code);

// Start the embedded Node runtime. Returns immediately; the runtime runs on
// its own thread. `entry_path` is the JS entry file to require, `data_dir` is
// the working directory. `out_cb` receives stdout/stderr chunks, `exit_cb`
// receives the exit code. Safe to call again after the previous run exited.
void node_embed_run(const char* entry_path, const char* data_dir,
                    cap_output_cb out_cb, cap_exit_cb exit_cb);

// Request the running embedded Node process to stop.
void node_embed_stop();

// Whether the embedded Node runtime is currently running.
int node_embed_is_running();

#ifdef __cplusplus
}
#endif
