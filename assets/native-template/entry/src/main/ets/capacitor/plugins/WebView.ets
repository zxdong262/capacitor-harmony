import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';
import { WebViewPathPayload } from '../BridgeInterfaces';

/**
 * `@capacitor/ionic-webview` — asset path access.
 *
 * On HarmonyOS the web app is always served from the built-in local server at
 * `http://localhost/`, so these methods resolve with that origin and accept the
 * setters for Ionic compatibility without changing behaviour.
 */
export class WebViewPlugin extends CapacitorPlugin {
  private static readonly ORIGIN: string = 'http://localhost/';

  getPluginId(): string {
    return 'WebView';
  }

  getMethods(): string[] {
    return ['getServerBasePath', 'setServerAssetPath', 'setServerBasePath', 'persistServerBasePath', 'clearServerBasePath'];
  }

  getServerBasePath(call: PluginCall): void {
    const result: WebViewPathPayload = { path: WebViewPlugin.ORIGIN };
    call.resolve(result);
  }

  setServerAssetPath(call: PluginCall): void {
    call.resolve();
  }

  setServerBasePath(call: PluginCall): void {
    call.resolve();
  }

  persistServerBasePath(call: PluginCall): void {
    call.resolve();
  }

  clearServerBasePath(call: PluginCall): void {
    call.resolve();
  }
}
