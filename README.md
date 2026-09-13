# capacitor-harmony

A **HarmonyOS / OpenHarmony platform adapter for Capacitor**. It lets you build
a Capacitor app that runs a real **ArkWeb WebView** plus an embedded **Node.js
runtime** inside a single HarmonyOS app — no external server required.

The adapter is built on top of
[`ohos-node-shared`](https://github.com/electerm/ohos-node-shared), which ships
a prebuilt, shared `libnode.so` (v24.2.0). The same approach is used in the real
world by [electerm-harmony](https://github.com/zxdong262/electerm-harmony).

> **Scope of the first edition.** This is *not* a full re-implementation of every
> Capacitor platform feature. It supports the **basic Capacitor contract** —
> bridge, plugin dispatch, local asset server, and the embedded Node.js runtime —
> enough to create an app with a WebView and Node.js. Plugins and surface areas
> outside that contract may be incomplete or absent.

---

## Features

- **WebView + Node.js in one app.** The ArkWeb WebView serves your web bundle
  from a virtual local server (`http://localhost/`), while an embedded Node.js
  process runs on a dedicated thread and serves HTTP on `127.0.0.1`.
- **Capacitor bridge.** JS → native (`window.harmonyBridge.postMessage`) and
  native → JS (`window.Capacitor.fromNative`) follow the standard Capacitor wire
  protocol, so `Capacitor.PluginHeaders`, `registerPlugin()`, events, and
  `Capacitor.getPlatform()` work as expected.
- **15 built-in core plugins.** `App`, `Device`, `Network`, `Preferences`,
  `Toast`, `Haptics`, `Clipboard`, `Browser`, `Console`, `Filesystem`,
  `StatusBar`, `Keyboard`, `SplashScreen`, `WebView`, and `Node`.
- **Web fallback for the Node API.** On non-Harmony platforms `capacitor-harmony`
  ships a no-op web implementation so app code stays platform-agnostic.
- **`cap sync harmony`** generates the native HarmonyOS project from the bundled
  ArkTS template and keeps it in sync with your `capacitor.config.ts`.

---

## Requirements

| Tool | Version |
|------|---------|
| Node.js | ≥ 18 |
| HarmonyOS SDK / DevEco Studio | API 12+ compatible; template compiles against 6.0.1 (API 21), Java 17/21 for `hvigor` |
| `@capacitor/core` / `@capacitor/cli` | ^6 \|\| ^7 \|\| ^8 |
| `ohos/hvigor` | provided by the HarmonyOS SDK |

The adapter itself runs where Node ≥ 18 runs (for the CLI). The generated
native project is built by the HarmonyOS SDK, not by this package.

---

## Installation

> The Capacitor CLI resolves a custom platform by its **package folder name**
> (`resolvePlatform()` looks up `node_modules/<platform>/package.json`), so the
> install must create `node_modules/harmony`. Install the published package
> under that alias:

```bash
npm install harmony@npm:capacitor-harmony @capacitor/core @capacitor/cli
```

For local development against a checkout of this repo:

```bash
npm install harmony@file:../capacitor-harmony @capacitor/core @capacitor/cli
```

Add the platform:

```bash
npx cap add harmony
```

This scaffolds a native HarmonyOS project under `harmony/` from the bundled
ArkTS template, copies your `webDir` into `rawfile/www`, and writes the runtime
config.

Sync after every web or config change:

```bash
npx cap sync harmony
```

Then fetch the embedded Node binary and build (see
[`docs/BUILD.md`](./docs/BUILD.md) for the full flow, emulator, and
troubleshooting):

```bash
./harmony/scripts/prepare-node.sh arm64   # device; use `x64` for the emulator
# open `harmony/` in DevEco Studio and build, or from the `harmony/` dir:
cd harmony && hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

---

## Quick start

A complete, runnable example lives in [`example/`](./example). It boots a Node
HTTP server from `node/main.js` and calls it from the WebView through the
native `Node.callApi` proxy (ArkWeb cannot open a socket to `127.0.0.1`
directly, so a plain `fetch('http://127.0.0.1:3000/...')` does **not** work
on-device).

`example/capacitor.config.ts`:

```ts
import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.example.harmonydemo',
  appName: 'HarmonyDemo',
  webDir: 'www',
  // NOTE: no `server.url` — production loads from the local asset server
  // (http://localhost/ serving rawfile/www). Only set `harmony.serverUrl`
  // to point at a dev server during development (see docs/BUILD.md §6).
  harmony: {
    nodeEntry: 'main.js',
    autostartNode: true,
  },
};

export default config;
```

`example/www/index.html` (relevant bits):

```html
<script>
  Capacitor.addListener('Node', 'stdout', (e) => console.log(e.line));
  Capacitor.nativePromise('Node', 'getStatus')
    .then((r) => console.log(r.running ? 'running' : 'stopped'));

  document.getElementById('ping').addEventListener('click', () => {
    Capacitor.nativePromise('Node', 'callApi', { path: '/api/hello' })
      .then((r) => console.log(r.body));
  });
</script>
```

`example/node/main.js`:

```js
const http = require('http');
http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify({ ok: true, node: process.version }));
}).listen(3000, '127.0.0.1');
```

See [`docs/BUILD.md`](./docs/BUILD.md) for building and running the HAP on a
device or emulator.

---

## Capacitor config (`harmony` namespace)

| Option | Type | Default | Meaning |
|--------|------|---------|---------|
| `harmony.bundleName` | `string` | `appId` | Overrides `appId` as the HAP bundle name. |
| `harmony.appLabel` | `string` | `appName` | Overrides `appName` as the app/ability label. |
| `harmony.nodeEntry` | `string` | `main.js` | Entry file under `rawfile/node/`. |
| `harmony.autostartNode` | `boolean` | `true` | Start the Node runtime automatically on launch. |
| `harmony.nodeDir` | `boolean` | `true` | Set `false` to disable the embedded Node runtime entirely. |
| `harmony.serverUrl` | `string` | `server.url` / `http://localhost/` | URL the WebView loads. Useful to point at a dev server. |
| `harmony.deviceTypes` | `string[]` | — | Overrides `module.json5` `deviceTypes`. |
| `harmony.permissions` | `string[]` | — | Appends `requestPermissions` entries to `module.json5`. |
| `logging` | `boolean` | `false` | Forward WebView `console.*` to `hilog`. |

---

## Using the Node runtime from JS

```ts
import { startNode, stopNode, getNodeStatus, onNodeStdout, nodeFetch } from 'capacitor-harmony/runtime';

await startNode();
await onNodeStdout(({ line }) => console.log(line));
// Proxied through native `Node.callApi` on-device (the WebView cannot reach
// 127.0.0.1 directly); plain fetch() against a dev server elsewhere.
const res = await nodeFetch('/api/hello', 3000);
const data = await res.json();
```

The full API is documented in [`docs/PLUGINS.md`](./docs/PLUGINS.md) (`Node`
section) and the source in
[`runtime/src/index.ts`](./runtime/src/index.ts).

---

## Documentation

- [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) — how the CLI, native
  template, bridge, and Node runtime fit together.
- [`docs/BUILD.md`](./docs/BUILD.md) — prerequisites and the HAP build flow.
- [`docs/PLUGINS.md`](./docs/PLUGINS.md) — built-in plugins, methods, events,
  and how to write a custom plugin.

---

## License

[MIT](./LICENSE)
