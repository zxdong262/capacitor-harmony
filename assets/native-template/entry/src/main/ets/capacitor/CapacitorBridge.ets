import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { CapacitorPlugin } from './CapacitorPlugin';
import { PluginCall } from './PluginCall';
import { LocalAssetServer } from './LocalAssetServer';
import { loadRuntimeConfig, extractNodeBundle } from './CapacitorConfig';
import { NodeRuntime } from './NodeRuntime';
import { registerPlugins } from './PluginRegistry';
import {
  AppUrlPayload,
  AppStatePayload,
  BackButtonPayload,
  BridgeMessage,
  EmptyPayload,
  HarmonyBridgeProxy,
  PluginHeader,
  PluginHost,
  PluginMethod,
  PluginResult,
  RuntimeConfig,
} from './BridgeInterfaces';

const TAG: string = 'CapacitorBridge';
const DOMAIN: number = 0x0000;

/** Method names the bridge routes to the plugin base class. */
const LISTENER_METHODS: string[] = ['addListener', 'removeListener', 'removeAllListeners'];

/**
 * The heart of the platform: owns the WebView controller, dispatches calls
 * coming from JS to native plugins, and pushes results back.
 *
 * Wire protocol (identical to `@capacitor/core`'s Android implementation):
 *
 *   JS -> native : window.harmonyBridge.postMessage(JSON.stringify(call))
 *   native -> JS : window.Capacitor.fromNative(result)
 */
export class CapacitorBridge implements PluginHost {
  private context: common.UIAbilityContext;
  private controller: webview.WebviewController;
  private assetServer: LocalAssetServer;
  private plugins: Map<string, CapacitorPlugin> = new Map();
  /** Open calls by callbackId, so we can echo pluginId/methodName back. */
  private calls: Map<string, PluginCall> = new Map();
  private config: RuntimeConfig;
  private node: NodeRuntime;
  private started: boolean = false;
  private isActive: boolean = true;
  /** Deep link / scheme URL the app was started with, replayed to `App`. */
  private launchUrl: string = '';

  constructor(context: common.UIAbilityContext, controller: webview.WebviewController) {
    this.context = context;
    this.controller = controller;
    this.assetServer = new LocalAssetServer(context);
    this.config = loadRuntimeConfig(context);
    this.node = new NodeRuntime(context);
  }

  /**
   * Register plugins, unpack the Node bundle and (optionally) boot Node.
   * Called once, from the page's `aboutToAppear`.
   */
  init(): void {
    if (this.started) {
      return;
    }
    this.started = true;

    registerPlugins(this);
    this.plugins.forEach((plugin: CapacitorPlugin) => {
      try {
        plugin.load();
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'load() of %{public}s failed: %{public}s', plugin.getPluginId(), String(e));
      }
    });
    hilog.info(DOMAIN, TAG, '%{public}d plugin(s) registered', this.plugins.size);

    if (this.config.node.enable) {
      const nodeDir: string = `${this.context.filesDir}/node`;
      try {
        this.node.setExtractReport(extractNodeBundle(this.context, nodeDir, this.config.node.files));
      } catch (e) {
        this.node.setExtractError(`extractNodeBundle crashed: ${String(e)}`);
      }
      this.node.configure(nodeDir, this.config.node.entry);
      if (this.config.node.autostart) {
        this.node.start();
      }
    }
  }

  // -------------------------------------------------------------------
  // Registration
  // -------------------------------------------------------------------

  registerPlugin(plugin: CapacitorPlugin): void {
    this.plugins.set(plugin.getPluginId(), plugin);
  }

  getPlugin(pluginId: string): CapacitorPlugin | undefined {
    return this.plugins.get(pluginId);
  }

  /**
   * The list advertised to JS as `Capacitor.PluginHeaders`.
   *
   * `addListener`/`removeListener` are deliberately absent: `@capacitor/core`
   * treats them as "special snowflakes" and routes them through the runtime's
   * own `addListenerNative` instead.
   */
  getPluginHeaders(): PluginHeader[] {
    const headers: PluginHeader[] = [];
    this.plugins.forEach((plugin: CapacitorPlugin) => {
      const methods: PluginMethod[] = [];
      plugin.getMethods().forEach((name: string) => {
        if (LISTENER_METHODS.includes(name)) {
          return;
        }
        const method: PluginMethod = { name: name, rtype: 'promise' };
        methods.push(method);
      });
      const header: PluginHeader = { name: plugin.getPluginId(), methods: methods };
      headers.push(header);
    });
    return headers;
  }

  getPluginHeadersJson(): string {
    return JSON.stringify(this.getPluginHeaders());
  }

  // -------------------------------------------------------------------
  // WebView wiring
  // -------------------------------------------------------------------

  /** The object handed to ArkWeb's `javaScriptProxy()`. */
  getProxyObject(): HarmonyBridgeProxy {
    return {
      postMessage: (message: string): void => {
        this.handleMessage(message);
      },
    };
  }

  /** Hook for `Web.onInterceptRequest()`. */
  handleInterceptRequest(request: WebResourceRequest): WebResourceResponse | null {
    if (!request) {
      return null;
    }
    const url: string = request.getRequestUrl();
    return this.assetServer.handleRequest(url, this.getPluginHeadersJson());
  }

  /** Called from `Web.onPageEnd()` — the document is ready for results. */
  onPageReady(): void {
    hilog.info(DOMAIN, TAG, 'page ready');
  }

  getContext(): common.UIAbilityContext {
    return this.context;
  }

  getConfig(): RuntimeConfig {
    return this.config;
  }

  getNodeRuntime(): NodeRuntime {
    return this.node;
  }

  /** URL the WebView should load: config override, else the local server. */
  getServerUrl(): string {
    if (this.config.serverUrl && this.config.serverUrl.length > 0) {
      return this.config.serverUrl;
    }
    return 'http://localhost/';
  }

  // -------------------------------------------------------------------
  // JS -> native
  // -------------------------------------------------------------------

  handleMessage(message: string): void {
    if (!message || message.length === 0) {
      return;
    }
    try {
      const msg: BridgeMessage = JSON.parse(message) as BridgeMessage;
      if (msg.type === 'js.error') {
        hilog.error(DOMAIN, TAG, 'js.error %{public}s', JSON.stringify(msg));
        return;
      }
      if (!msg.callbackId || !msg.pluginId || !msg.methodName) {
        hilog.warn(DOMAIN, TAG, 'malformed bridge message: %{public}s', message);
        return;
      }
      this.dispatch(msg);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'failed to handle bridge message: %{public}s', String(e));
    }
  }

  private dispatch(msg: BridgeMessage): void {
    const call: PluginCall = new PluginCall(
      this,
      msg.pluginId,
      msg.methodName,
      msg.callbackId,
      msg.options ?? ({} as Record<string, Object>),
    );
    this.calls.set(msg.callbackId, call);

    const plugin: CapacitorPlugin | undefined = this.plugins.get(msg.pluginId);
    if (!plugin) {
      hilog.warn(DOMAIN, TAG, 'no plugin named %{public}s', msg.pluginId);
      call.unavailable(`${msg.pluginId} is not installed`);
      return;
    }

    const methodName: string = msg.methodName;
    if (methodName === 'addListener') {
      plugin.addListener(call);
      return;
    }
    if (methodName === 'removeListener') {
      plugin.removeListener(call);
      return;
    }
    if (methodName === 'removeAllListeners') {
      plugin.removeAllListeners(call);
      return;
    }

    if (!plugin.getMethods().includes(methodName)) {
      call.unimplemented(`${msg.pluginId}.${methodName} is not implemented on HarmonyOS`);
      return;
    }

    try {
      // Indexing the instance keeps `this` bound (unlike extracting the
      // function into a variable first), which is exactly what the dynamic
      // dispatch in CapacitorPlugin subclasses needs.
      const handler: Record<string, (c: PluginCall) => void> =
        plugin as Object as Record<string, (c: PluginCall) => void>;
      handler[methodName](call);
    } catch (e) {
      hilog.error(DOMAIN, TAG, '%{public}s.%{public}s threw: %{public}s', msg.pluginId, methodName, String(e));
      if (!call.isFinished()) {
        call.reject(String(e), 'ERROR');
      }
    }
  }

  // -------------------------------------------------------------------
  // native -> JS
  // -------------------------------------------------------------------

  sendResult(callbackId: string, data: Object, success: boolean, save: boolean): void {
    const call: PluginCall | undefined = this.calls.get(callbackId);
    const result: PluginResult = {
      callbackId: callbackId,
      pluginId: call ? call.pluginId : '',
      methodName: call ? call.methodName : '',
      success: success,
      data: data,
      error: success ? null : data,
      save: save,
    };
    if (save === false) {
      this.calls.delete(callbackId);
    }
    this.evalJs(`window.Capacitor.fromNative(${JSON.stringify(result)})`);
  }

  evalJs(script: string): void {
    try {
      this.controller.runJavaScript(script).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'runJavaScript failed: %{public}s %{public}s', String(err.code), err.message);
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'runJavaScript threw: %{public}s', String(e));
    }
  }

  /** Fire an event on a plugin, from native code. */
  notifyListeners(pluginId: string, eventName: string, data: Object): void {
    const plugin: CapacitorPlugin | undefined = this.plugins.get(pluginId);
    if (plugin) {
      plugin.notifyListeners(eventName, data);
    }
  }

  // -------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------

  onResume(): void {
    this.isActive = true;
    const resumed: AppStatePayload = { isActive: true };
    this.notifyListeners('App', 'appStateChange', resumed);
    const emptyResume: EmptyPayload = {};
    this.notifyListeners('App', 'resume', emptyResume);
  }

  onPause(): void {
    this.isActive = false;
    const paused: AppStatePayload = { isActive: false };
    this.notifyListeners('App', 'appStateChange', paused);
    const emptyPause: EmptyPayload = {};
    this.notifyListeners('App', 'pause', emptyPause);
  }

  onDestroy(): void {
    this.isActive = false;
    this.node.stop();
  }

  isAppActive(): boolean {
    return this.isActive;
  }

  /**
   * Hand a `Want` (deep link, share target, ...) to the `App` plugin.
   *
   * @returns true when the URL was consumed by a JS listener.
   */
  handleNewWant(want: Want): void {
    const url: string = want?.uri ?? '';
    if (url.length === 0) {
      return;
    }
    if (this.launchUrl.length === 0) {
      // Remember it so `App.getLaunchUrl()` can report it later.
      this.launchUrl = url;
    }
    const opened: AppUrlPayload = { url: url, sourceApplication: want?.bundleName ?? '' };
    this.notifyListeners('App', 'appUrlOpen', opened);
  }

  getLaunchUrl(): string {
    return this.launchUrl;
  }

  /**
   * Back-gesture / hardware back handling.
   *
   * Mirrors Android: if JS registered a `backButton` listener, native does
   * nothing and lets the app decide (usually by calling `App.exitApp()`).
   *
   * @returns true when the event was consumed and the app should not exit.
   */
  onBackPressed(): boolean {
    const app: CapacitorPlugin | undefined = this.plugins.get('App');
    if (!app) {
      return false;
    }
    if (!app.hasListeners('backButton')) {
      return false;
    }
    const back: BackButtonPayload = { canGoBack: this.controller.accessBackward() };
    app.notifyListeners('backButton', back);
    return true;
  }
}
