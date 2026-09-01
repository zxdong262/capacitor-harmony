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
// The exact Node embedder surface changes between majors; this file follows
// the Node 24 embedder API (CommonEnvironmentSetup + LoadEnvironment). The
// canonical reference is `test/embedding/embedtest.cc` in the Node tree.

#include <napi/native_api.h>

#include <cstdlib>
#include <cstring>
#include <functional>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include <libplatform/libplatform.h>

// Node's bundled NAPI headers (node_api.h -> js_native_api.h) declare the same
// napi_* symbols as the OHOS NAPI headers we use for the addon, but with a
// different `env` type (`node_api_basic_env` vs OHOS `napi_env`), which makes
// the two sets conflict ("conflicting types for napi_get_instance_data", ...).
// We only embed Node's V8 + platform API (we use v8 directly for the host
// bridge, and OHOS NAPI for the addon), so suppress Node's NAPI declarations
// by pre-defining their include guards. node.h itself only references
// `napi_module` / `napi_addon_register_func` from that set (in AddLinkedBinding
// overloads we never call), so forward-declare just those two to let the
// header parse.
#define SRC_NODE_API_H_
#define SRC_JS_NATIVE_API_H_
typedef struct napi_module napi_module;
typedef void* napi_addon_register_func;
#include <node.h>
#undef SRC_NODE_API_H_
#undef SRC_JS_NATIVE_API_H_

#include <uv.h>

// ----------------------------------------------------------------------------
// Global state
// ----------------------------------------------------------------------------

static std::mutex g_state_mutex;
static std::thread g_node_thread;
static bool g_running = false;
static int g_exit_code = 0;

static node::Environment* g_env = nullptr;

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

// JS run inside the new Environment: rewire process.stdout / process.stderr so
// each chunk is forwarded to ArkTS, then load the user entry (process.argv[1]).
// globalThis.__capHost is installed from C++ (see InstallHostBridge) — it is a
// plain JS object whose `write(level, line)` forwards to ArkTS.
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
  require(process.argv[1]);
})();
)js";

// ----------------------------------------------------------------------------
// Node thread
// ----------------------------------------------------------------------------

static void InstallHostBridge(v8::Isolate* isolate, v8::Local<v8::Context> context) {
  v8::HandleScope scope(isolate);
  v8::Context::Scope context_scope(context);

  // host.write(level, line) -> EmitOutput(...) on the Node thread.
  v8::Local<v8::Function> write_fn = v8::Function::New(
      context,
      [](const v8::FunctionCallbackInfo<v8::Value>& info) {
        v8::Isolate* iso = info.GetIsolate();
        if (info.Length() < 2) {
          return;
        }
        v8::String::Utf8Value level(iso, info[0]);
        v8::String::Utf8Value line(iso, info[1]);
        EmitOutput(std::string(*level, level.length()),
                   std::string(*line, line.length()));
      })
      .ToLocalChecked();

  v8::Local<v8::Object> host = v8::Object::New(isolate);
  host->Set(context, v8::String::NewFromUtf8(isolate, "write").ToLocalChecked(),
            write_fn)
      .FromMaybe(false);

  context->Global()
      ->Set(context, v8::String::NewFromUtf8(isolate, "__capHost").ToLocalChecked(),
            host)
      .FromMaybe(false);
}

static void NodeThreadMain(std::string entry_path, std::string data_dir) {
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (g_running) {
      return;
    }
    g_running = true;
  }

  std::vector<std::string> args = {"node", entry_path};

  std::shared_ptr<node::InitializationResult> result =
      node::InitializeOncePerProcess(args);
  for (const std::string& err : result->errors()) {
    EmitOutput("stderr", "InitializeOncePerProcess: " + err);
  }
  if (result->early_return()) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_running = false;
    return;
  }

  std::unique_ptr<node::MultiIsolatePlatform> platform =
      node::MultiIsolatePlatform::Create(4);
  v8::V8::InitializePlatform(platform.get());
  v8::V8::Initialize();

  // chdir into the data dir so relative requires / file IO work as expected.
  if (!data_dir.empty()) {
    uv_chdir(data_dir.c_str());
  }

  std::vector<std::string> errors;
  std::unique_ptr<node::CommonEnvironmentSetup> setup =
      node::CommonEnvironmentSetup::Create(platform.get(), &errors,
                                           result->args(), result->exec_args());
  if (!setup) {
    for (const std::string& err : errors) {
      EmitOutput("stderr", "CreateEnvironment: " + err);
    }
    EmitOutput("stderr", "CreateEnvironment failed");
    v8::V8::Dispose();
    v8::V8::DisposePlatform();
    node::TearDownOncePerProcess();
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_running = false;
    return;
  }

  node::Environment* env = setup->env();
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_env = env;
  }

  // Install the host bridge (globalThis.__capHost) before running JS.
  InstallHostBridge(setup->isolate(), setup->context());

  // Load + run the bootstrap (rewires stdout/stderr, requires the entry file).
  v8::MaybeLocal<v8::Value> loadenv_ret =
      node::LoadEnvironment(env, std::string_view(kBootstrap));
  if (loadenv_ret.IsEmpty()) {
    EmitOutput("stderr", "LoadEnvironment threw during startup");
  }

  // Block on the libuv loop until the entry exits or stop() is called.
  g_exit_code = node::SpinEventLoop(env).FromMaybe(1);

  // Teardown.
  node::Stop(env);
  setup.reset();  // frees the Environment / Isolate
  v8::V8::Dispose();
  v8::V8::DisposePlatform();
  node::TearDownOncePerProcess();

  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_running = false;
    g_env = nullptr;
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
