// capacitor_node.cpp — OHOS NAPI addon for capacitor-harmony.
//
// This translation unit includes ONLY the OHOS NAPI headers
// (<napi/native_api.h>). It exposes a NAPI module whose methods start/stop the
// embedded Node runtime and register listeners for its stdout/stderr/exit
// events. The actual Node embedding lives in node_embed.cpp, which uses a
// different (Node's own) NAPI ABI; the two communicate purely through the C
// function pointers declared in node_bridge.h. Keeping the two NAPI ABIs in
// separate TUs avoids the "conflicting types for napi_*" clash that occurs
// when both are parsed in one translation unit (Node declares the napi_*
// functions with `node_api_basic_env`, OHOS with `napi_env` — same underlying
// pointer type, different type name).
//
// The module is linked against the prebuilt shared libnode.so shipped by
// https://github.com/electerm/ohos-node-shared.

#include <napi/native_api.h>

#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>

#include "node_bridge.h"

// ----------------------------------------------------------------------------
// Global state
// ----------------------------------------------------------------------------

static std::mutex g_state_mutex;
static napi_threadsafe_function g_output_tsfn = nullptr;
static napi_threadsafe_function g_exit_tsfn = nullptr;

// ----------------------------------------------------------------------------
// Output capture
// ----------------------------------------------------------------------------

struct OutputPayload {
  std::string level;
  std::string line;
};

// C callback invoked from the Node thread (node_embed.cpp). Forwards the line
// to ArkTS through the output threadsafe function.
static void CapEmitOutput(const char* level, const char* line) {
  if (g_output_tsfn == nullptr) {
    return;
  }
  OutputPayload* data = new OutputPayload{level, line};
  napi_status status =
      napi_call_threadsafe_function(g_output_tsfn, data, napi_tsfn_nonblocking);
  if (status != napi_ok) {
    delete data;
  }
}

// C callback invoked when the embedded Node process exits.
static void CapEmitExit(int code) {
  if (g_exit_tsfn == nullptr) {
    return;
  }
  int* data = new int(code);
  napi_status status =
      napi_call_threadsafe_function(g_exit_tsfn, data, napi_tsfn_nonblocking);
  if (status != napi_ok) {
    delete data;
  }
}

// ----------------------------------------------------------------------------
// Threadsafe-function proxies (run on the ArkTS thread)
// ----------------------------------------------------------------------------

static void OutputTsfnCall(napi_env env, napi_value js_cb, void* context,
                           void* data) {
  OutputPayload* payload = static_cast<OutputPayload*>(data);
  if (payload == nullptr) {
    return;
  }
  napi_value args[2];
  napi_create_string_utf8(env, payload->level.c_str(), payload->level.size(),
                          &args[0]);
  napi_create_string_utf8(env, payload->line.c_str(), payload->line.size(),
                          &args[1]);
  napi_value result;
  napi_call_function(env, js_cb, js_cb, 2, args, &result);
  delete payload;
}

static void ExitTsfnCall(napi_env env, napi_value js_cb, void* context,
                         void* data) {
  int* code = static_cast<int*>(data);
  if (code == nullptr) {
    return;
  }
  napi_value args[1];
  napi_create_int32(env, *code, &args[0]);
  napi_value result;
  napi_call_function(env, js_cb, js_cb, 1, args, &result);
  delete code;
}

// ----------------------------------------------------------------------------
// Public NAPI exports
// ----------------------------------------------------------------------------

static napi_value NapiStart(napi_env env, napi_callback_info info) {
  if (node_embed_is_running()) {
    napi_value running;
    napi_get_boolean(env, true, &running);
    return running;
  }

  size_t argc = 2;
  napi_value argv[2];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc < 2) {
    napi_throw_error(env, nullptr,
                     "start(entryPath, dataDir) requires two arguments");
    return nullptr;
  }

  size_t len = 0;
  napi_get_value_string_utf8(env, argv[0], nullptr, 0, &len);
  std::string entry(len, '\0');
  napi_get_value_string_utf8(env, argv[0], &entry[0], len + 1, &len);

  napi_get_value_string_utf8(env, argv[1], nullptr, 0, &len);
  std::string data_dir(len, '\0');
  napi_get_value_string_utf8(env, argv[1], &data_dir[0], len + 1, &len);

  node_embed_run(entry.c_str(), data_dir.c_str(), CapEmitOutput, CapEmitExit);

  napi_value ok;
  napi_get_boolean(env, true, &ok);
  return ok;
}

static napi_value NapiStop(napi_env env, napi_callback_info info) {
  node_embed_stop();
  return nullptr;
}

static napi_value NapiIsRunning(napi_env env, napi_callback_info info) {
  napi_value result;
  napi_get_boolean(env, node_embed_is_running() != 0, &result);
  return result;
}

static napi_value NapiSetOutputListener(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc < 1) {
    return nullptr;
  }
  if (g_output_tsfn != nullptr) {
    napi_release_threadsafe_function(g_output_tsfn, napi_tsfn_release);
    g_output_tsfn = nullptr;
  }
  napi_value resource_name;
  napi_create_string_utf8(env, "capacitor-node-output", NAPI_AUTO_LENGTH,
                          &resource_name);
  napi_create_threadsafe_function(env, argv[0], nullptr, resource_name, 0, 1,
                                  nullptr, nullptr, nullptr, OutputTsfnCall,
                                  &g_output_tsfn);
  return nullptr;
}

static napi_value NapiSetExitListener(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc < 1) {
    return nullptr;
  }
  if (g_exit_tsfn != nullptr) {
    napi_release_threadsafe_function(g_exit_tsfn, napi_tsfn_release);
    g_exit_tsfn = nullptr;
  }
  napi_value resource_name;
  napi_create_string_utf8(env, "capacitor-node-exit", NAPI_AUTO_LENGTH,
                          &resource_name);
  napi_create_threadsafe_function(env, argv[0], nullptr, resource_name, 0, 1,
                                  nullptr, nullptr, nullptr, ExitTsfnCall,
                                  &g_exit_tsfn);
  return nullptr;
}

// ----------------------------------------------------------------------------
// Module registration
// ----------------------------------------------------------------------------

static napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor descriptors[] = {
      {"start", nullptr, NapiStart, nullptr, nullptr, nullptr, napi_default,
       nullptr},
      {"stop", nullptr, NapiStop, nullptr, nullptr, nullptr, napi_default,
       nullptr},
      {"isRunning", nullptr, NapiIsRunning, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"setOutputListener", nullptr, NapiSetOutputListener, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"setExitListener", nullptr, NapiSetExitListener, nullptr, nullptr,
       nullptr, napi_default, nullptr},
  };
  napi_define_properties(
      env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
  return exports;
}

NAPI_MODULE(capacitor_node, Init)
