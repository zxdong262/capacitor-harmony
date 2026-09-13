# Plugins

`capacitor-harmony` ships **15 built-in native plugins** under
`entry/src/main/ets/capacitor/plugins/`. The method names listed below are
exactly what each plugin declares in `getMethods()` (and therefore what ends up
in `Capacitor.PluginHeaders`). The events listed are emitted through
`notifyListeners()`.

> All methods are **promise-style** on the JS side (`Capacitor.nativePromise`
> / `registerPlugin` returns a promise) unless noted. `addListener` /
> `removeListener` / `removeAllListeners` are handled by the runtime and are
> **not** part of `getMethods()` — do not re-declare them.

---

## Built-in plugin summary

| Plugin | Methods | Events |
|--------|---------|--------|
| `App` | `exitApp`, `getInfo`, `getLaunchUrl`, `getState`, `minimizeApp` | `appStateChange`, `resume`, `pause`, `appUrlOpen`, `backButton` |
| `Device` | `getInfo`, `getId`, `getBatteryInfo`, `getLanguageCode`, `getLanguageTag` | — |
| `Network` | `getStatus` | `networkStatusChange` |
| `Preferences` | `configure`, `get`, `set`, `remove`, `keys`, `clear`, `migrate`, `removeOld` | — |
| `Toast` | `show` | — |
| `Haptics` | `impact`, `vibrate`, `selectionStart`, `selectionChanged`, `selectionEnd` | — |
| `Clipboard` | `read`, `write` | — |
| `Browser` | `open`, `close` | — |
| `Console` | `log`, `debug`, `info`, `warn`, `error` | — |
| `Filesystem` | `readFile`, `writeFile`, `appendFile`, `deleteFile`, `mkdir`, `rmdir`, `readdir`, `stat`, `getUri`, `rename`, `copy`, `checkPermissions`, `requestPermissions`, `downloadFile`, `uploadFile` | — |
| `StatusBar` | `setStyle`, `setBackgroundColor`, `show`, `hide`, `getInfo`, `setOverlaysWebView` | — |
| `Keyboard` | `show`, `hide`, `setAccessoryBarVisible`, `setScroll`, `setStyle`, `setResizeMode` | `keyboardWillShow`, `keyboardDidShow`, `keyboardWillHide`, `keyboardDidHide` |
| `SplashScreen` | `show`, `hide` | `splashScreenHidden` (fired on first `addListener`) |
| `WebView` | `getServerBasePath`, `setServerAssetPath`, `setServerBasePath`, `persistServerBasePath`, `clearServerBasePath` | — |
| `Node` | `start`, `stop`, `getStatus`, `getInfo` | `stdout`, `stderr`, `exit` |

---

## Notes per plugin

- **App** — `appStateChange`/`resume`/`pause` are driven by lifecycle
  (`onResume`/`onPause`). `appUrlOpen` fires from `onNewWant` (deep links).
  `backButton` fires from `onBackPress` only when a JS listener is registered;
  otherwise the default (exit) behaviour applies.
- **Network** — `getStatus` returns `{ connected, connectionType }`;
  `networkStatusChange` carries the same shape.
- **Preferences** — backed by `@ohos.data.preferences` (a KV store scoped to the
  app). `configure({ group })` selects the store; `migrate`/`removeOld` are
  compatibility shims from `@capacitor/preferences`.
- **Filesystem** — operates on the app sandbox (`filesDir`/`cacheDir`), so no
  runtime permission is needed. `downloadFile`/`uploadFile` are declared but
  **unimplemented in the first edition** (they resolve with an error).
- **Console** — `bridge.js` already forwards WebView `console.*` to the native
  logger when `logging: true` is set; this plugin lets native code push log
  lines the other way (drains to `hilog`).
- **Keyboard** — reports show/hide through `window`'s `keyboardHeightChange`;
  the four events carry `{ keyboardHeight }`. The method calls resolve
  immediately (HarmonyOS has no per-call keyboard promise semantics).
- **SplashScreen** — `addListener('splashScreenHidden', …)` fires the event
  immediately on registration (the splash is a WebView overlay managed by the
  app; there is no separate native splash window in the first edition).
- **WebView** — always returns the local asset-server origin
  (`http://localhost/`). The setters are present for API compatibility but the
  first edition serves from `rawfile/www` only.
- **Node** — see the dedicated section below.

---

## The `Node` plugin & the `capacitor-harmony/runtime` API

The embedded Node.js runtime is reached through the `Node` plugin. On
HarmonyOS these calls boot the real `libnode.so` and run `rawfile/node/<entry>`.
On every other platform the same API is available with a **no-op web fallback**,
so app code stays platform-agnostic.

Import from `capacitor-harmony/runtime`:

```ts
import {
  startNode, stopNode, getNodeStatus, getNodeInfo,
  onNodeStdout, onNodeStderr, onNodeExit, nodeFetch,
  Node,
} from 'capacitor-harmony/runtime';
```

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `startNode()` | `Promise<{ running: boolean }>` | Start the Node runtime (no-op on web). |
| `stopNode()` | `Promise<{ running: boolean }>` | Stop the Node runtime. |
| `getNodeStatus()` | `Promise<{ running: boolean }>` | Is the runtime running? |
| `getNodeInfo()` | `Promise<{ entry, entryPath, dir }>` | Entry file name, absolute path, working dir. |
| `nodeFetch(path, port=3000, init?)` | `Promise<Response>` | `fetch('http://127.0.0.1:<port><path>')` — reaches the Node HTTP backend bound to localhost. |

### Events

| Event | Payload | Description |
|-------|---------|-------------|
| `stdout` | `{ line: string }` | A line written to the Node process's stdout. |
| `stderr` | `{ line: string }` | A line written to stderr. |
| `exit` | `{ code: number }` | Fired once when the Node process exits. |

```ts
await startNode();

const off = await onNodeStdout(({ line }) => console.log('[node]', line));
await onNodeExit(({ code }) => console.log('node exited', code));

const res = await nodeFetch('/api/hello', 3000);   // http://127.0.0.1:3000/api/hello
const data = await res.json();

await off.remove();   // or: onNodeStdout(...).then(h => h.remove())
```

The native contract (`NodePlugin`) is defined in
[`runtime/src/definitions.ts`](../../runtime/src/definitions.ts); the binding
and helpers live in [`runtime/src/index.ts`](../../runtime/src/index.ts).

---

## Writing a custom plugin

A native plugin is an ArkTS class under
`entry/src/main/ets/capacitor/plugins/` that extends `CapacitorPlugin`.

```ts
// entry/src/main/ets/capacitor/plugins/Echo.ets
import { common } from '@kit.AbilityKit';
import { PluginHost } from '../BridgeInterfaces';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';

export class EchoPlugin extends CapacitorPlugin {
  getPluginId(): string { return 'Echo'; }

  getMethods(): string[] { return ['echo']; }

  echo(call: PluginCall): void {
    const value = call.getString('value');
    call.resolve({ value } as Object);
  }
}
```

### Surface it to JS

The CLI regenerates `PluginRegistry.ets` on every `cap sync harmony`. For a
bundled plugin (a `.ets` file dropped into `plugins/`), it is picked up
automatically by filename → `Foo.ets` exports `FooPlugin`.

For a **third-party npm plugin**, declare the source in its `package.json`:

```json
{
  "capacitor": {
    "harmony": { "src": "dist/harmony/echo.ets", "id": "Echo", "className": "EchoPlugin" }
  }
}
```

`cap sync harmony` copies `src` into `plugins/` and registers it.

### `PluginCall` helpers

`PluginCall` exposes typed accessors for the incoming `options` object:
`getString`, `getBoolean`, `getNumber`, `getObject`, `getArray`, plus
`resolve(data?)` and `reject(message, code?)`.

### Events from a plugin

```ts
this.notifyListeners('myEvent', { foo: 'bar' } as Object);
```

JS subscribes with `Capacitor.addListener('MyPlugin', 'myEvent', cb)`. If you
need a one-shot event delivered even before a listener exists, use
`notifyListeners(name, data, /* retainUntilConsumed */ true)`.

> **Do not** list `addListener` / `removeListener` / `removeAllListeners` in
> `getMethods()` — the runtime handles those specially and they are excluded
> from `Capacitor.PluginHeaders`.

---

## Plugin dispatch under the hood

When JS calls `Capacitor.plugins.MyPlugin.method(...)`:

1. `bridge.js` sends `{ callbackId, pluginId, methodName, options }` to native
   via `window.harmonyBridge.postMessage`.
2. `CapacitorBridge.handleMessage` → `dispatch` looks up the plugin by
   `pluginId`, validates `getMethods().includes(methodName)`, and calls
   `plugin[methodName](call)` (dynamic dispatch, preserving `this`).
3. The plugin calls `call.resolve(data)` / `call.reject(...)`, which builds the
   response and delivers it via `window.Capacitor.fromNative`.
4. For events, the plugin calls `notifyListeners`, which sends `save: true`
   results to every registered callback id — keeping the JS listener alive.
