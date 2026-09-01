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
| HarmonyOS SDK / DevEco Studio | API 12+ (command line build supported) |
| `@capacitor/core` / `@capacitor/cli` | ^6 \|\| ^7 \|\| ^8 |
| `ohos/hvigor` | provided by the HarmonyOS SDK |

The adapter itself runs where Node ≥ 18 runs (for the CLI). The generated
native project is built by the HarmonyOS SDK, not by this package.

---

## Installation

```bash
npm install capacitor-harmony @capacitor/core @capacitor/cli
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

---

## Quick start

A complete, runnable example lives in [`example/`](./example). It boots a Node
HTTP server from `node/main.js` and calls it from the WebView with `fetch`.

`example/capacitor.config.ts`:

```ts
import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.example.harmonydemo',
  appName: 'HarmonyDemo',
  webDir: 'www',
  server: { url: 'http://localhost/', cleartext: true },
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
    fetch('http://127.0.0.1:3000/api/hello')
      .then((res) => res.json())
      .then((data) => console.log(data));
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
const data = await nodeFetch('/api/hello', 3000); // http://127.0.0.1:3000/api/hello
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
