import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { PluginHost } from '../BridgeInterfaces';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';
import { NodeApiResultPayload, NodeExitPayload, NodeInfoPayload, NodeLinePayload, NodeRunningPayload } from '../BridgeInterfaces';
import { NodeRuntime } from '../NodeRuntime';

/**
 * `capacitor-harmony/node` — control the embedded Node.js runtime from JS.
 *
 * The typical pattern is to boot a Node HTTP server in `main.js` and talk to
 * it from the WebView. Because ArkWeb's WebView cannot open a raw socket to
 * `127.0.0.1` (loopback is sandboxed), the WebView must NOT `fetch()` the
 * backend directly. Instead it calls `Node.callApi`, which proxies the request
 * from the native side (native HTTP *can* reach the loopback) and returns the
 * response body to JS.
 *
 * Methods: `start`, `stop`, `getStatus`, `getInfo`, `callApi`.
 * Events:  `stdout`, `stderr`, `exit`.
 */
export class NodePlugin extends CapacitorPlugin {
  private node: NodeRuntime;

  constructor(bridge: PluginHost, context: common.UIAbilityContext) {
    super(bridge, context);
    this.node = bridge.getNodeRuntime();
    this.node.onOutput((level: string, line: string) => {
      const out: NodeLinePayload = { line: line };
      this.notifyListeners(level === 'error' ? 'stderr' : 'stdout', out);
    });
    this.node.onExit((code: number) => {
      const exited: NodeExitPayload = { code: code };
      this.notifyListeners('exit', exited);
    });
  }

  getPluginId(): string {
    return 'Node';
  }

  getMethods(): string[] {
    return ['start', 'stop', 'getStatus', 'getInfo', 'callApi'];
  }

  start(call: PluginCall): void {
    const ok: boolean = this.node.start();
    if (ok) {
      const started: NodeRunningPayload = { running: true };
      call.resolve(started);
    } else {
      call.reject(this.node.getLastError() || 'node failed to start', 'START_FAILED');
    }
  }

  stop(call: PluginCall): void {
    this.node.stop();
    const stopped: NodeRunningPayload = { running: false };
    call.resolve(stopped);
  }

  getStatus(call: PluginCall): void {
    const status: NodeRunningPayload = { running: this.node.isRunning() };
    call.resolve(status);
  }

  getInfo(call: PluginCall): void {
    const info: NodeInfoPayload = {
      entry: this.node.getEntry(),
      entryPath: this.node.getEntryPath(),
      dir: this.node.getDir(),
    };
    call.resolve(info);
  }

  /**
   * Proxy an HTTP request to the embedded Node backend from the native side.
   *
   * ArkWeb's WebView cannot open a socket to `127.0.0.1`, so the web layer
   * calls this instead of `fetch('http://127.0.0.1:<port>/...')`. The native
   * HTTP stack can reach the loopback, then we hand the body back to JS.
   *
   * Options: `path` (default `/api/hello`), `method` (GET|POST, default GET).
   * Resolves with `{ status: number, body: string }`.
   */
  callApi(call: PluginCall): void {
    const path: string = call.getString('path', '/api/hello');
    const method: string = call.getString('method', 'GET').toUpperCase();
    const url: string = `http://127.0.0.1:3000${path}`;
    const req = http.createHttp();
    const httpMethod: http.RequestMethod =
      method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET;
    req
      .request(url, {
        method: httpMethod,
        connectTimeout: 5000,
        readTimeout: 5000,
      })
      .then((resp) => {
        const body: string =
          typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
        const result: NodeApiResultPayload = { status: resp.responseCode, body: body };
        call.resolve(result);
        req.destroy();
      })
      .catch((err: Error) => {
        call.reject(`node api call failed: ${err.message}`, 'NODE_API_ERROR');
        req.destroy();
      });
  }
}
