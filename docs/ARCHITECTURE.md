# Architecture

This document explains how the pieces of `capacitor-harmony` fit together:
the npm CLI, the generated native HarmonyOS project, the WebView bridge, and
the embedded Node.js runtime.

```
┌─────────────────────────────────────────────────────────────┐
│  Your Capacitor web app (rawfile/www)                        │
│   uses @capacitor/core  +  capacitor-harmony/runtime          │
└───────────────┬───────────────────────────┬──────────────────┘
                │ JS → native               │ native → JS
                │ window.harmonyBridge      │ window.Capacitor
                │   .postMessage(json)      │   .fromNative(json)
                ▼                            ▲
┌─────────────────────────────────────────────────────────────┐
│  ArkWeb WebView  (javaScriptProxy + runJavaScript)            │
│   bridge.js injected as first <head> script                   │
└───────────────┬─────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────┐
│  CapacitorBridge (ArkTS)  — the hub                           │
│   • routes JS calls to plugins                                │
│   • owns the WebviewController, LocalAssetServer, plugins     │
│   • owns the NodeRuntime                                      │
└──────┬───────────────────────┬──────────────────────────────┘
       ▼                        ▼
┌─────────────────────┐   ┌────────────────────────────────────┐
│ 15 core plugins     │   │ NodeRuntime (ArkTS)                  │
│ (ArkTS, in          │   │   → libcapacitor_node.so (NAPI)     │
│  entry/.../plugins) │   │     → dlopen(libnode.so, v24.2.0)   │
└─────────────────────┘   └────────────────────────────────────┘
```

---

## 1. The npm package (CLI side)

`capacitor-harmony` is an npm package that declares itself as a Capacitor
platform:

```json
"capacitor": { "platform": "harmony" }
```

When `@capacitor/cli` runs `npx cap add harmony` / `copy` / `update` / `open`,
it invokes the corresponding `capacitor:*` script with these environment
variables set and the **cwd = this package directory**:

- `CAPACITOR_ROOT_DIR` — the user's app project root
- `CAPACITOR_WEB_DIR` — absolute path to the built web bundle
- `CAPACITOR_CONFIG` — JSON of the resolved `capacitor.config.ts`
- `CAPACITOR_PLATFORM_NAME` — `harmony`

The CLI sources (`src/`) implement those four commands:

| Command | Source | What it does |
|---------|--------|--------------|
| `add` | `src/add.ts` | Scaffold `harmony/` from `assets/native-template`, then `copy`. |
| `copy` | `src/copy.ts` | Copy `webDir` → `rawfile/www`, `node/` → `rawfile/node`, write `capacitor.config.json`, regenerate `PluginRegistry.ets`, apply identity/module overrides. |
| `update` | `src/update.ts` | Re-copy the native template (keeping config), then `copy`. |
| `open` | `src/open.ts` | Open the generated project for editing (DevEco / folder). |

Key generated artefacts in `harmony/`:

- `entry/src/main/resources/rawfile/www/**` — the web app.
- `entry/src/main/resources/rawfile/node/**` — the Node backend, plus
  `node/.file-list.json` (a listing, because `resourceManager` has no directory
  API).
- `entry/src/main/resources/rawfile/capacitor.config.json` — the runtime config
  the ArkTS side reads.
- `entry/src/main/ets/capacitor/PluginRegistry.ets` — the generated plugin
  registry (matches the handwritten default in the template; CLI regenerates
  it on every `sync`).

### `harmony` config → runtime config mapping

`src/configure.ts` turns the user's `capacitor.config.ts` into the
`RuntimeConfig` JSON the ArkTS side consumes:

| `capacitor.config.ts` | `RuntimeConfig` |
|-----------------------|-----------------|
| `appId` / `appName` | `appId` / `appName` |
| `server.url` (or `harmony.serverUrl`) | `serverUrl` (default `http://localhost/`) |
| `harmony.nodeEntry` | `node.entry` (default `main.js`) |
| `harmony.autostartNode !== false` | `node.autostart` (default `true`) |
| `harmony.nodeDir !== false` | `node.enable` (default `true`) |
| `logging === true` or `harmony.logging === true` | `logging.enabled` |

---

## 2. The native template (ArkTS side)

`assets/native-template/` is a complete HarmonyOS "stage model" project. The
Capacitor-specific code lives under
`entry/src/main/ets/capacitor/`:

| File | Role |
|------|------|
| `BridgeInterfaces.ets` | `PluginHost` interface + `RuntimeConfig` type (breaks the circular dependency between `CapacitorBridge` and the plugins). |
| `CapacitorBridge.ets` | The hub. Owns the WebView, asset server, plugin map, and node runtime. |
| `CapacitorPlugin.ets` | Base class for native plugins: `getPluginId()`, `getMethods()`, listener bookkeeping, `notifyListeners()`. |
| `PluginCall.ets` | A single JS→native call: option accessors + `resolve()`/`reject()`. |
| `LocalAssetServer.ets` | Virtual local server for `http://localhost/`, served from `rawfile/www`. |
| `NodeRuntime.ets` | Thin wrapper over `libcapacitor_node.so`. |
| `CapacitorConfig.ets` | Loads `capacitor.config.json`; extracts `rawfile/node/**` into the writable `filesDir`. |
| `PluginRegistry.ets` | Maps plugin id → ArkTS class (regenerated by the CLI). |
| `bridgeInstance.ets` | A holder that breaks the `EntryAbility` ↔ `CapacitorBridge` import cycle. |
| `plugins/*.ets` | The 15 built-in plugins. |

`EntryAbility.ets` (`entry/src/main/ets/entryability/`) initializes the web
engine and wires lifecycle callbacks (`onForeground`/`onBackground`/`onDestroy`/
`onNewWant`) to the bridge. `pages/Index.ets` creates the `CapacitorBridge`,
registers the JS proxy (`javaScriptProxy`), and the intercept request handler
(`onInterceptRequest`).

---

## 3. The bridge wire protocol

`bridge.js` (injected into the WebView as the first `<head>` script) is a port
of Capacitor's `native-bridge.ts`. It is what makes `Capacitor.getPlatform()`
return `'harmony'` and routes plugin calls.

**JS → native** (one JSON object per call):

```json
{ "callbackId": "12", "pluginId": "App", "methodName": "getInfo", "options": {} }
```

Dispatched to the native side via `window.harmonyBridge.postMessage(JSON.stringify(msg))`.

**native → JS** (response or event):

```json
{ "callbackId": "12", "pluginId": "App", "methodName": "getInfo",
  "success": true, "data": { "...": "..." }, "save": false }
```

Delivered via `window.Capacitor.fromNative(obj)` (which ArkWeb calls through
`runJavaScript`).

`save: true` keeps the JS callback registered — that is the event-listener
mechanism (`addListener`). The runtime mirrors Android's
`call.setKeepAlive(true)` + `data.put("save", call.isKeptAlive())`.

### Plugin headers and the listener special-cases

`CapacitorBridge.getPluginHeaders()` builds the `Capacitor.PluginHeaders` array
injected into the WebView. It **excludes** `addListener` / `removeListener` /
`removeAllListeners` (those are routed by the runtime's own `addListenerNative`)
and emits `{ name, methods: [{ name, rtype: 'promise' }] }` for every other
method — matching Android's `JSExport` / `PluginMethod` (`promise`, `callback`,
`none`; only non-`none` rtypes are emitted).

Dynamic dispatch in `CapacitorBridge.dispatch()`:

```ts
const handler = plugin as Object as Record<string, (c: PluginCall) => void>;
handler[methodName](call);   // preserves `this` binding
```

The `as Object as Record<...>` cast satisfies ArkTS's strictness while keeping
the real `this`.

---

## 4. The local asset server

`LocalAssetServer.handleRequest(url, pluginHeadersJson)` intercepts requests to
`http://localhost/` and serves them from `rawfile/www` via
`resourceManager.getRawFileContentSync()`. It handles:

- SPA fallback (unknown paths without an extension → `index.html`).
- MIME types by extension.
- `_capacitor_file_` prefix → reads a real filesystem path via `@ohos.file.fs`
  (used by `Capacitor.convertFileSrc()`).
- Injection of `bridge.js` (with `__CAPACITOR_PLUGIN_HEADERS__` replaced by the
  real headers JSON) as the first `<head>` script of `index.html`.

---

## 5. The embedded Node.js runtime

This is the part that makes `capacitor-harmony` interesting: a **real Node.js**
runs inside the app.

```
rawfile/node/**  ──extract──▶  <filesDir>/node/**
                                          │
                                          ▼
Node.ets (plugin) ──getInfo/start/stop──▶ NodeRuntime.ets
                                          │  import
                                          ▼
                      libcapacitor_node.so  (NAPI module, ours)
                                          │  dlopen at runtime
                                          ▼
                      libnode.so  (ohos-node-shared, v24.2.0, prebuilt)
```

- `Node.ets` is the Capacitor plugin exposed to JS. Its `start/stop/getStatus/
  getInfo` methods drive `NodeRuntime`; it forwards `stdout`/`stderr`/`exit`
  events to JS listeners.
- `NodeRuntime.ets` wraps `libcapacitor_node.so`. `configure(dir, entry)` sets
  the extracted `filesDir/node` and the entry file; `start()` spawns Node on its
  own thread.
- `native/node-runtime/capacitor_node.cpp` is the NAPI module that:
  - uses the documented Node 22+ embedder C++ API
    (`node::InitializeOncePerProcess`, `MultiIsolatePlatform::Create`,
    `node::CreateEnvironment`, `node::LoadEnvironment`, `node::SpinEventLoop`,
    …) on a `std::thread`;
  - rewires `process.stdout`/`stderr._write` to post lines back to ArkTS via a
    `napi_threadsafe_function`;
  - runs the app's entry file with `require(process.argv[1])`.
- `libnode.so` is **not** committed. `scripts/prepare-node.sh` downloads it from
  the `ohos-node-shared` release, verifies the SHA-256, and **rejects PIE
  builds** (a true `--shared` `.so` is required; a PIE artifact would crash on
  V8's `AllowHeapAllocationInRelease::IsAllowed()` assertion).

### Why a shared library, not a static build?

`ohos-node-shared` builds Node with `--shared`, producing a genuine
`ET_DYN`/`libnode.so` that `dlopen()`s at runtime. That keeps the NAPI glue
small and lets the Node binary be fetched/verified separately from the app
binary.

---

## Build-time vs run-time responsibilities

| Phase | Owner | Output |
|-------|-------|--------|
| `npx cap sync harmony` | this npm package (Node ≥ 18) | `harmony/` native project + `rawfile` contents |
| download `libnode.so` | `scripts/prepare-node.sh` | `entry/libs/<abi>/libnode.so` |
| compile `libcapacitor_node.so` | HarmonyOS NDK / hvigor | native library linked into the HAP |
| build HAP | `hvigorw assembleHap` | installable `.hap` |
| extract `rawfile/node/**` | app launch (`CapacitorConfig.ets`) | writable `filesDir/node` |
| start Node | app launch (if `autostart: true`) | running Node process |
