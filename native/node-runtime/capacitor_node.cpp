// capacitor_node.cpp — embedded Node.js runtime for capacitor-harmony.
//
// This NAPI module is linked against the prebuilt shared `libnode.so` shipped
// by https://github.com/electerm/ohos-node-shared (built with `--shared`, so it
// dlopen()s cleanly instead of crashing on V8's TLS assertion like a PIE build
// would).
//
// It runs the app's entry file on a dedicated thread using Node's embedder
// API, captures stdout/stderr, and pushes output + exit events back to ArkTS
// through `napi_threadsafe_function`s.
//
// Build prerequisites (see scripts/prepare-headers.sh and prepare-node.sh):
//   * Node.js v24.2.0 headers  (node.h, v8.h, libplatform.h, uv.h, ...)
//   * libnode.so for the target ABI in entry/libs/<abi>/
//
// The exact Node embedder surface changes between majors; if it does not
// compile verbatim, compare against `node/sample/embedtest.cc` of the matching
// Node version — the shape used here follows the Node 22+ API.

#include <napi/native_api.h>

#include <cstdlib>
#include <cstring>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <libplatform/libplatform.h>
#include <node.h>
#include <uv.h>

// ----------------------------------------------------------------------------
// Global state
// ----------------------------------------------------------------------------

static std::mutex g_state_mutex;
static std::thread g_node_thread;
static bool g_running = false;
static int g_exit_code = 0;

static node::MultiIsolatePlatform* g_platform = nullptr;
static node::Isolate* g_isolate = nullptr;
static node::Environment* g_env = nullptr;
static uv_loop_t* g_loop = nullptr;

// Threadsafe functions that push data to ArkTS.
static napi_threadsafe_function g_output_tsfn = nullptr;
static napi_threadsafe_function g_exit_tsfn = nullptr;

// ----------------------------------------------------------------------------
// Output capture
// ----------------------------------------------------------------------------

struct OutputPayload {
  std::string level;
  std::string line;
};

// Called from the Node thread.  `level` is "stdout" or "stderr".
static void EmitOutput(const std::string& level, const std::string& line) {
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

// JS run inside the new Environment: expose the host bridge on globalThis and
// rewire process.stdout / process.stderr so each chunk is forwarded to ArkTS.
static const char kBootstrap[] = R"js(
(function () {
  const host = globalThis.__capHost;
  if (!host || typeof host.write !== 'function') return;
  function rewire(name) {
    const stream = process[name];
    if (!stream || typeof stream._write !== 'function') return;
    const original = stream._write.bind(stream);
    stream._write = function (chunk, encoding, callback) {
      try { host.write(name, chunk.toString()); } catch (e) {}
      original(chunk, encoding, callback);
    };
  }
  rewire('stdout');
  rewire('stderr');
})();
)js";

// ----------------------------------------------------------------------------
// Node thread
// ----------------------------------------------------------------------------

static napi_value HostWrite(napi_env env, napi_callback_info info);

static void NodeThreadMain(std::string entry_path, std::string data_dir) {
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (g_running) {
      return;
    }
    g_running = true;
  }

  std::vector<std::string> args = {"node", entry_path};
  std::vector<std::string> exec_args;
  std::vector<std::string> errors;

  int rc = node::InitializeOncePerProcess(args, exec_args, errors);
  if (rc != 0) {
    EmitOutput("stderr", "InitializeOncePerProcess failed with code " + std::to_string(rc));
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_running = false;
    return;
  }

  g_platform = node::MultiIsolatePlatform::Create(4);
  v8::V8::InitializePlatform(g_platform);
  v8::V8::Initialize();

  uv_loop_t loop;
  if (uv_loop_init(&loop) != 0) {
    EmitOutput("stderr", "uv_loop_init failed");
    v8::V8::ShutdownPlatform();
    node::TearDownOncePerProcess();
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_running = false;
    return;
  }
  g_loop = &loop;

  node::IsolateSettings isolate_settings;
  g_isolate = node::CreateIsolate(
      g_platform,
      isolate_settings,
      args,
      exec_args,
      node::EnvironmentFlags::kOwnsProcessState | node::EnvironmentFlags::kOwnsInspector,
      nullptr);

  if (g_isolate == nullptr) {
    EmitOutput("stderr", "CreateIsolate failed");
    uv_loop_close(&loop);
    v8::V8::ShutdownPlatform();
    node::TearDownOncePerProcess();
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_running = false;
    g_loop = nullptr;
    return;
  }

  g_env = node::CreateEnvironment(
      g_isolate,
      g_platform,
      args,
      exec_args,
      node::EnvironmentFlags::kOwnsProcessState | node::EnvironmentFlags::kOwnsInspector);

  if (g_env == nullptr) {
    EmitOutput("stderr", "CreateEnvironment failed");
    node::FreeIsolate(g_isolate);
    uv_loop_close(&loop);
    v8::V8::ShutdownPlatform();
    node::TearDownOncePerProcess();
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_running = false;
    g_isolate = nullptr;
    g_loop = nullptr;
    return;
  }

  // Load the entry file (it is argv[1]) and the stdout/stderr re-wiring.
  node::LoadEnvironment(g_env, [entry_path](napi_env env) -> napi_value {
    // Expose the host bridge so the bootstrap can reach it.
    napi_value global;
    napi_value host_obj;
    napi_value write_fn;
    if (napi_get_global(env, &global) == napi_ok &&
        napi_create_object(env, &host_obj) == napi_ok &&
        napi_create_function(env, "write", NAPI_AUTO_LENGTH, HostWrite, nullptr, &write_fn) == napi_ok) {
      napi_set_named_property(env, host_obj, "write", write_fn);
      napi_set_named_property(env, global, "__capHost", host_obj);
    }

    // Run the bootstrap (rewires stdout/stderr).
    napi_value bootstrap;
    napi_value bootstrap_result;
    if (napi_create_string_utf8(env, kBootstrap, NAPI_AUTO_LENGTH, &bootstrap) == napi_ok) {
      napi_run_script(env, bootstrap, &bootstrap_result);
    }

    // Load and execute the user's entry file.
    napi_value main;
    napi_value main_result;
    if (napi_create_string_utf8(env, "require(process.argv[1]);", NAPI_AUTO_LENGTH, &main) == napi_ok) {
      napi_run_script(env, main, &main_result);
    }
    return main_result;
  });

  // Block on the libuv loop until the entry exits or stop() is called.
  g_exit_code = node::SpinEventLoop(g_env);

  // Teardown.
  node::Stop(g_env);
  node::FreeEnvironment(g_env);
  node::FreeIsolate(g_isolate);
  uv_loop_close(&loop);
  v8::V8::ShutdownPlatform();
  node::TearDownOncePerProcess();

  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_running = false;
    g_isolate = nullptr;
    g_env = nullptr;
    g_loop = nullptr;
  }

  // Inform ArkTS the process ended.
  if (g_exit_tsfn != nullptr) {
    int* code = new int(g_exit_code);
    napi_call_threadsafe_function(g_exit_tsfn, code, napi_tsfn_nonblocking);
  }
}

// ----------------------------------------------------------------------------
// NAPI plumbing
// ----------------------------------------------------------------------------

static napi_value HostWrite(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc < 2) {
    return nullptr;
  }
  size_t level_len = 0;
  napi_get_value_string_utf8(env, argv[0], nullptr, 0, &level_len);
  std::string level(level_len, '\0');
  napi_get_value_string_utf8(env, argv[0], &level[0], level_len + 1, &level_len);

  size_t line_len = 0;
  napi_get_value_string_utf8(env, argv[1], nullptr, 0, &line_len);
  std::string line(line_len, '\0');
  napi_get_value_string_utf8(env, argv[1], &line[0], line_len + 1, &line_len);

  EmitOutput(level, line);
  return nullptr;
}

// Proxy: called on the ArkTS thread when a thread calls g_output_tsfn.
static void OutputTsfnCall(napi_env env, napi_value js_cb, void* context, void* data) {
  OutputPayload* payload = static_cast<OutputPayload*>(data);
  if (payload == nullptr) {
    return;
  }
  napi_value args[2];
  napi_create_string_utf8(env, payload->level.c_str(), payload->level.size(), &args[0]);
  napi_create_string_utf8(env, payload->line.c_str(), payload->line.size(), &args[1]);
  napi_value result;
  napi_call_function(env, js_cb, js_cb, 2, args, &result);
  delete payload;
}

static void ExitTsfnCall(napi_env env, napi_value js_cb, void* context, void* data) {
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
  size_t argc = 2;
  napi_value argv[2];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc < 2) {
    napi_throw_error(env, nullptr, "start(entryPath, dataDir) requires two arguments");
    return nullptr;
  }
  size_t len = 0;
  napi_get_value_string_utf8(env, argv[0], nullptr, 0, &len);
  std::string entry(len, '\0');
  napi_get_value_string_utf8(env, argv[0], &entry[0], len + 1, &len);

  napi_get_value_string_utf8(env, argv[1], nullptr, 0, &len);
  std::string data_dir(len, '\0');
  napi_get_value_string_utf8(env, argv[1], &data_dir[0], len + 1, &len);

  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (g_running) {
      napi_value running;
      napi_get_boolean(env, true, &running);
      return running;
    }
  }

  // chdir into the data dir so relative requires / file IO work as expected.
  if (!data_dir.empty()) {
    uv_chdir(data_dir.c_str());
  }

  std::thread t(NodeThreadMain, entry, data_dir);
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_node_thread = std::move(t);
    napi_value ok;
    napi_get_boolean(env, true, &ok);
    return ok;
  }
}

static napi_value NapiStop(napi_env env, napi_callback_info info) {
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (!g_running) {
      return nullptr;
    }
  }
  if (g_env != nullptr) {
    node::Stop(g_env);
  }
  if (g_loop != nullptr) {
    uv_stop(g_loop);
  }
  return nullptr;
}

static napi_value NapiIsRunning(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  napi_value result;
  napi_get_boolean(env, g_running, &result);
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
  napi_create_string_utf8(env, "capacitor-node-output", NAPI_AUTO_LENGTH, &resource_name);
  napi_create_threadsafe_function(env, argv[0], nullptr, resource_name, 0, 1, nullptr, nullptr,
                                 nullptr, OutputTsfnCall, &g_output_tsfn);
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
  napi_create_string_utf8(env, "capacitor-node-exit", NAPI_AUTO_LENGTH, &resource_name);
  napi_create_threadsafe_function(env, argv[0], nullptr, resource_name, 0, 1, nullptr, nullptr,
                                 nullptr, ExitTsfnCall, &g_exit_tsfn);
  return nullptr;
}

// ----------------------------------------------------------------------------
// Module registration
// ----------------------------------------------------------------------------

static napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor descriptors[] = {
      {"start", nullptr, NapiStart, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"stop", nullptr, NapiStop, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"isRunning", nullptr, NapiIsRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"setOutputListener", nullptr, NapiSetOutputListener, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"setExitListener", nullptr, NapiSetExitListener, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
  return exports;
}

NAPI_MODULE(capacitor_node, Init)
