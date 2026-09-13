# capacitor-harmony

面向 **HarmonyOS / OpenHarmony 的 Capacitor 平台适配器**。它让你用 Capacitor
构建一个同时运行 **ArkWeb WebView** 与 **内置 Node.js 运行时** 的鸿蒙应用 ——
不需要任何外部服务器。

本适配器基于
[`ohos-node-shared`](https://github.com/electerm/ohos-node-shared) 实现，后者
提供预编译的共享库 `libnode.so`（v24.2.0）。同样的方式也应用于真实项目
[electerm-harmony](https://github.com/zxdong262/electerm-harmony)。

> **首版范围说明。** 这不是对 Capacitor 各平台特性的完整复刻，只实现
> **最基础的 Capacitor 契约** —— 桥接、插件分发、本地资源服务器、内置 Node.js
> 运行时 —— 足以支撑「WebView + Node.js」的应用。契约之外的插件或能力可能尚未
> 完整支持。

---

## 特性

- **WebView 与 Node.js 同处一个应用。** ArkWeb WebView 通过虚拟本地服务器
  （`http://localhost/`）加载你的网页包，内置的 Node.js 进程在独立线程运行，
  并通过 `127.0.0.1` 提供 HTTP 服务。
- **Capacitor 桥接。** JS → 原生（`window.harmonyBridge.postMessage`）与原生 →
  JS（`window.Capacitor.fromNative`）遵循标准 Capacitor 线协议，因此
  `Capacitor.PluginHeaders`、`registerPlugin()`、事件机制与
  `Capacitor.getPlatform()` 均按预期工作。
- **15 个内置核心插件。** `App`、`Device`、`Network`、`Preferences`、`Toast`、
  `Haptics`、`Clipboard`、`Browser`、`Console`、`Filesystem`、`StatusBar`、
  `Keyboard`、`SplashScreen`、`WebView`、`Node`。
- **Node API 的 Web 兜底实现。** 在非鸿蒙平台上，`capacitor-harmony` 提供
  no-op 的 Web 实现，应用代码可保持平台无关。
- **`cap sync harmony`。** 从内置的 ArkTS 模板生成原生鸿蒙工程，并根据你的
  `capacitor.config.ts` 保持同步。

---

## 环境要求

| 工具 | 版本 |
|------|------|
| Node.js | ≥ 18 |
| HarmonyOS SDK / DevEco Studio | API 12+（支持命令行构建） |
| `@capacitor/core` / `@capacitor/cli` | ^6 \|\| ^7 \|\| ^8 |
| `ohos/hvigor` | 由 HarmonyOS SDK 提供 |

适配器本身的 CLI 只需 Node ≥ 18 即可运行；生成的原生工程由 HarmonyOS SDK
构建，不依赖本包。

---

## 安装

```bash
npm install capacitor-harmony @capacitor/core @capacitor/cli
```

添加平台：

```bash
npx cap add harmony
```

这会从内置的 ArkTS 模板在 `harmony/` 下生成原生鸿蒙工程，把 `webDir` 拷贝到
`rawfile/www`，并写入运行时配置。

每次改动网页或配置后同步：

```bash
npx cap sync harmony
```

---

## 快速开始

完整可运行的示例见 [`example/`](./example)。它从 `node/main.js` 启动一个 Node
HTTP 服务，并通过 `fetch` 从 WebView 调用它。

`example/capacitor.config.ts`：

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

`example/www/index.html`（关键片段）：

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

`example/node/main.js`：

```js
const http = require('http');
http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify({ ok: true, node: process.version }));
}).listen(3000, '127.0.0.1');
```

构建并在设备/模拟器上运行 HAP 的方法见
[`docs/BUILD.md`](./docs/BUILD.md)。

---

## Capacitor 配置（`harmony` 命名空间）

| 选项 | 类型 | 默认值 | 含义 |
|------|------|--------|------|
| `harmony.bundleName` | `string` | `appId` | 覆盖 `appId`，作为 HAP 的 bundleName。 |
| `harmony.appLabel` | `string` | `appName` | 覆盖 `appName`，作为应用/Ability 标签。 |
| `harmony.nodeEntry` | `string` | `main.js` | `rawfile/node/` 下的入口文件。 |
| `harmony.autostartNode` | `boolean` | `true` | 启动时是否自动启动 Node 运行时。 |
| `harmony.nodeDir` | `boolean` | `true` | 设为 `false` 可完全关闭内置 Node 运行时。 |
| `harmony.serverUrl` | `string` | `server.url` / `http://localhost/` | WebView 加载的地址，可指向开发服务器。 |
| `harmony.deviceTypes` | `string[]` | — | 覆盖 `module.json5` 的 `deviceTypes`。 |
| `harmony.permissions` | `string[]` | — | 向 `module.json5` 追加 `requestPermissions` 项。 |
| `logging` | `boolean` | `false` | 将 WebView 的 `console.*` 转发到 `hilog`。 |

---

## 从 JS 使用 Node 运行时

```ts
import { startNode, stopNode, getNodeStatus, onNodeStdout, nodeFetch } from 'capacitor-harmony/runtime';

await startNode();
await onNodeStdout(({ line }) => console.log(line));
const data = await nodeFetch('/api/hello', 3000); // http://127.0.0.1:3000/api/hello
```

完整 API 见 [`docs/PLUGINS.md`](./docs/PLUGINS.md)（Node 一节）与源码
[`runtime/src/index.ts`](./runtime/src/index.ts)。

---

## 文档

- [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) —— CLI、原生模板、桥接与
  Node 运行时如何协作。
- [`docs/BUILD.md`](./docs/BUILD.md) —— 前置条件与 HAP 构建流程。
- [`docs/PLUGINS.md`](./docs/PLUGINS.md) —— 内置插件、方法、事件，以及如何
  编写自定义插件。

---

## 许可证

[MIT](./LICENSE)
