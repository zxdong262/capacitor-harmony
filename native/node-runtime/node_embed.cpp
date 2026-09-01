// node_embed.cpp — embedded Node.js runtime for capacitor-harmony.
//
// This translation unit includes ONLY Node's own headers (node.h, v8.h,
// libplatform.h, uv.h). It must NOT include the OHOS NAPI headers: Node's
// bundled NAPI shim declares the same napi_* symbols as OHOS NAPI but with a
// different `env` type, and the two ABIs clash if brought into one TU. The
// OHOS side lives in capacitor_node.cpp and talks to this code only through
// the C function pointers declared in node_bridge.h.
//
// It is linked against the prebuilt shared libnode.so shipped by
// https://github.com/electerm/ohos-node-shared (built with --shared so it
// dlopen()s cleanly instead of crashing on V8's TLS assertion).
//
// The exact Node embedder surface changes between majors; this file follows
// the Node 24 embedder API (CommonEnvironmentSetup + LoadEnvironment). The
// canonical reference is `test/embedding/embedtest.cc` in the Node tree.

#include "node_bridge.h"

#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include <libplatform/libplatform.h>
#include <node.h>
#include <uv.h>

static std::mutex g_state_mutex;
static std::thread g_node_thread;
static bool g_running = false;
static int g_exit_code = 0;
static node::Environment* g_env = nullptr;

// Callbacks supplied by the OHOS side at start time.
static cap_output_cb g_out_cb = nullptr;
static cap_exit_cb g_exit_cb = nullptr;

static void EmitOutput(const std::string& level, const std::string& line) {
  if (g_out_cb != nullptr) {
    g_out_cb(level.c_str(), line.c_str());
  }
}

// JS run inside the new Environment: rewire process.stdout / process.stderr so
// each chunk is forwarded to the OHOS side, then load the user entry
// (process.argv[1]). globalThis.__capHost is installed from C++ (see
// InstallHostBridge) — a plain JS object whose `write(level, line)` forwards to
// the OHOS side.
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

static void InstallHostBridge(v8::Isolate* isolate,
                              v8::Local<v8::Context> context) {
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
      ->Set(context,
            v8::String::NewFromUtf8(isolate, "__capHost").ToLocalChecked(), host)
      .FromMaybe(false);
}

static void NodeThreadMain(std::string entry_path, std::string data_dir,
                           cap_output_cb out_cb, cap_exit_cb exit_cb) {
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (g_running) {
      return;
    }
    g_running = true;
    g_out_cb = out_cb;
    g_exit_cb = exit_cb;
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
    g_out_cb = nullptr;
    g_exit_cb = nullptr;
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
    g_out_cb = nullptr;
    g_exit_cb = nullptr;
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

  cap_exit_cb exit_cb = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_running = false;
    g_env = nullptr;
    g_out_cb = nullptr;
    exit_cb = g_exit_cb;
    g_exit_cb = nullptr;
  }

  // Inform the OHOS side the process ended.
  if (exit_cb != nullptr) {
    exit_cb(g_exit_code);
  }
}

void node_embed_run(const char* entry_path, const char* data_dir,
                    cap_output_cb out_cb, cap_exit_cb exit_cb) {
  if (entry_path == nullptr) {
    return;
  }
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (g_running) {
      return;
    }
  }
  std::thread t(NodeThreadMain, std::string(entry_path),
                data_dir != nullptr ? std::string(data_dir) : std::string(),
                out_cb, exit_cb);
  std::lock_guard<std::mutex> lock(g_state_mutex);
  g_node_thread = std::move(t);
}

void node_embed_stop() {
  node::Environment* env = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (!g_running) {
      return;
    }
    env = g_env;
  }
  if (env != nullptr) {
    node::Stop(env);
  }
}

int node_embed_is_running() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_running ? 1 : 0;
}
