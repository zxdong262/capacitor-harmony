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
