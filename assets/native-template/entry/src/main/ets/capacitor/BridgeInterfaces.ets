import { common } from '@kit.AbilityKit';
import { NodeRuntime } from './NodeRuntime';

/**
 * Shared types for the capacitor-harmony bridge.
 *
 * The wire format is byte-for-byte the one `@capacitor/core` expects:
 *
 *   JS -> native : { callbackId, pluginId, methodName, options }
 *   native -> JS : { callbackId, pluginId, methodName, success, data, error, save }
 */

/** A call coming from the WebView. */
export interface BridgeMessage {
  callbackId: string;
  pluginId: string;
  methodName: string;
  options?: Record<string, Object>;
  /** 'js.error' for window error reports, 'message' otherwise. */
  type?: string;
}

/** The result we hand back to `window.Capacitor.fromNative()`. */
export interface PluginResult {
  callbackId: string;
  pluginId: string;
  methodName: string;
  success: boolean;
  data: Object;
  error?: Object | null;
  /**
   * When true the JS side keeps the callback registered so it can be invoked
   * again — this is how event listeners work.
   */
  save?: boolean;
}

export interface PluginErrorData {
  message: string;
  code?: string;
  error?: Object;
}

export interface PluginMethod {
  name: string;
  rtype?: string;
}

/** Mirrors `PluginHeader` from @capacitor/core. */
export interface PluginHeader {
  name: string;
  methods: PluginMethod[];
}

/** The object registered with ArkWeb `javaScriptProxy()`. */
export interface HarmonyBridgeProxy {
  postMessage: (message: string) => void;
}

/**
 * The slice of `CapacitorBridge` a plugin is allowed to see.
 *
 * Declared as an interface rather than using the concrete class so that the
 * generated `PluginRegistry` can be imported by the bridge without creating a
 * circular dependency.
 */
export interface PluginHost {
  getContext(): common.UIAbilityContext;
  /** The embedded Node.js runtime wrapper, exposed to the Node plugin. */
  getNodeRuntime(): NodeRuntime;
  /** Register a plugin instance built by `PluginRegistry`. */
  registerPlugin(plugin: Object): void;
  /**
   * Hand a result back to `window.Capacitor.fromNative()`.
   *
   * @param save keep the JS callback registered so it can fire again — this is
   *   how event listeners stay alive.
   */
  sendResult(callbackId: string, data: Object, success: boolean, save: boolean): void;
  /** Fire-and-forget script evaluation inside the WebView. */
  evalJs(script: string): void;
  /** True while the ability is in the foreground. */
  isAppActive(): boolean;
  /** Deep link the app was launched with, empty when started normally. */
  getLaunchUrl(): string;
}

export interface AppState {
  isActive: boolean;
}

export interface AppUrl {
  url: string;
  sourceApplication?: string;
}

/** Shape of `rawfile/capacitor.config.json`, written by `cap sync harmony`. */
export interface RuntimeConfig {
  appId: string;
  appName: string;
  /** URL the WebView loads.  Defaults to the built-in asset server. */
  serverUrl: string;
  node: NodeRuntimeOptions;
  logging: LoggingOptions;
}

export interface NodeRuntimeOptions {
  enable: boolean;
  /** Entry file inside `rawfile/node`. */
  entry: string;
  autostart: boolean;
  /** Relative file paths under `rawfile/node` to unpack at launch. */
  files?: string[];
}

export interface LoggingOptions {
  enabled: boolean;
}

export const DEFAULT_RUNTIME_CONFIG: RuntimeConfig = {
  appId: '',
  appName: '',
  serverUrl: 'http://localhost/',
  node: { enable: false, entry: 'main.js', autostart: false },
  logging: { enabled: false },
};

// ---------------------------------------------------------------------------
// Plugin result / event payload types
//
// ArkTS forbids both index signatures (arkts-no-indexed-signatures) and
// object literals that do not correspond to an explicitly declared class or
// interface (arkts-no-untyped-obj-literals). So every dynamic-looking payload
// gets its own named interface with explicit properties.
// ---------------------------------------------------------------------------

/** Empty event payloads (`resume`, `pause`, `splashScreenHidden`). */
export interface EmptyPayload {
}

/** `App.appStateChange` / `App.getState`. */
export interface AppStatePayload {
  isActive: boolean;
}

/** `App.backButton`. */
export interface BackButtonPayload {
  canGoBack: boolean;
}

/** `App.appUrlOpen`. */
export interface AppUrlPayload {
  url: string;
  sourceApplication: string;
}

/** `App.getInfo`. */
export interface AppInfoPayload {
  id: string;
  name: string;
  build: string;
  version: string;
}

/** `App.getUrl` and friends — a single `url` field. */
export interface UrlPayload {
  url: string;
}

/** `Device.getInfo`. */
export interface DeviceInfoPayload {
  name: string;
  model: string;
  platform: string;
  operatingSystem: string;
  osVersion: string;
  manufacturer: string;
  isVirtual: boolean;
  memUsed: number;
  diskFree: number;
  diskTotal: number;
  realDiskFree: number;
  realDiskTotal: number;
  webViewVersion: string;
  apiLevel: number;
}

/** `Device.getId`. */
export interface DeviceIdPayload {
  identifier: string;
}

/** `Device.getBatteryInfo`. */
export interface BatteryPayload {
  batteryLevel: number;
  isCharging: boolean;
}

/** A single `value: string` result (language code, locale code, ...). */
export interface StringValuePayload {
  value: string;
}

/** `Filesystem.readFile` (text or base64). */
export interface FileDataPayload {
  data: string;
}

/** `Filesystem.readdir`. */
export interface FileListPayload {
  files: string[];
}

/** `Filesystem.stat`. */
export interface FileStatPayload {
  type: string;
  size: number;
  ctime: number;
  mtime: number;
  uri: string;
}

/** `Filesystem.getUri` — a single `uri` field. */
export interface FileUriPayload {
  uri: string;
}

/** `Filesystem.checkPermissions`. */
export interface StoragePermPayload {
  publicStorage: string;
}

/** Keyboard height events. */
export interface KeyboardHeightPayload {
  keyboardHeight: number;
}

/** `Network.getStatus` / `Network.onStatusChange`. */
export interface NetworkStatusPayload {
  connected: boolean;
  connectionType: string;
}

/** Node.js stdout/stderr lines. */
export interface NodeLinePayload {
  line: string;
}

/** Node.js process exit. `log` is the boot log captured at exit time. */
export interface NodeExitPayload {
  code: number;
  log: string;
}

/** `Node.start` / `Node.stop`. `error` is empty on success. */
export interface NodeRunningPayload {
  running: boolean;
  error: string;
}

/**
 * `Node.getStatus`.
 *
 * `error` is the last failure reason (native start error, crash signal, …) and
 * `log` is the tail of the native boot log. Both exist so a runtime that never
 * comes up can be diagnosed on the device without `hdc hilog`.
 */
export interface NodeStatusPayload {
  running: boolean;
  error: string;
  log: string;
}

/** `Node.getLog` — the tail of the native boot log. */
export interface NodeLogPayload {
  log: string;
}

/** `Node.getInfo`. */
export interface NodeInfoPayload {
  entry: string;
  entryPath: string;
  dir: string;
}

/** `Node.callApi` — a backend HTTP response proxied from the native side. */
export interface NodeApiResultPayload {
  status: number;
  body: string;
}

/** `Preferences.get` — value may be any JSON value or null. */
export interface PrefValuePayload {
  value: Object | null;
}

/** `Preferences.keys`. */
export interface PrefKeysPayload {
  keys: string[];
}

/** `Preferences.migrate`. */
export interface PrefMigratePayload {
  migrated: string[];
  existing: string[];
}

/** `StatusBar.getInfo`. */
export interface StatusBarInfoPayload {
  visible: boolean;
  style: string;
  color: string;
  backgroundColor: string;
  contentOffset: number;
  overlays: boolean;
}

/** `WebView.getOriginalUrl` — a single `path` field. */
export interface WebViewPathPayload {
  path: string;
}

/** `Clipboard.read`. */
export interface ClipboardValuePayload {
  value: string;
  type: string;
}
