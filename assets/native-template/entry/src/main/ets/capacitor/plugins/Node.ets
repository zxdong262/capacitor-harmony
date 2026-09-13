import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { PluginHost } from '../BridgeInterfaces';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';
import {
  NodeApiResultPayload,
  NodeExitPayload,
  NodeInfoPayload,
  NodeLinePayload,
  NodeLogPayload,
  NodeRunningPayload,
  NodeStatusPayload,
} from '../BridgeInterfaces';
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
 * `getStatus` / `getLog` also hand back the last error and the tail of the
 * native boot log (`<node dir>/node-boot.log`), so a backend that never comes
 * up can be diagnosed straight from the app UI.
 *
 * Methods: `start`, `stop`, `getStatus`, `getInfo`, `getLog`, `callApi`.
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
      const exited: NodeExitPayload = { code: code, log: this.node.getLastLog() };
      this.notifyListeners('exit', exited);
    });
  }

  getPluginId(): string {
    return 'Node';
  }

  getMethods(): string[] {
    return ['start', 'stop', 'getStatus', 'getInfo', 'getLog', 'callApi'];
  }

  start(call: PluginCall): void {
    const ok: boolean = this.node.start();
    if (ok) {
      const started: NodeRunningPayload = { running: true, error: '' };
      call.resolve(started);
    } else {
      const failed: NodeRunningPayload = {
        running: false,
        error: this.node.getLastError() || 'node failed to start',
      };
      call.reject(failed.error, 'START_FAILED', failed);
    }
  }

  stop(call: PluginCall): void {
    this.node.stop();
    const stopped: NodeRunningPayload = { running: false, error: '' };
    call.resolve(stopped);
  }

  getStatus(call: PluginCall): void {
    const status: NodeStatusPayload = {
      running: this.node.isRunning(),
      error: this.node.getLastError(),
      log: this.node.readLog(),
      extract: this.node.getExtractInfo(),
    };
    call.resolve(status);
  }

  /** Tail of `<node dir>/node-boot.log` — the runtime's own trace. */
  getLog(call: PluginCall): void {
    const payload: NodeLogPayload = { log: this.node.readLog() };
    call.resolve(payload);
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
   * Options: `path` (default `/api/hello`), `method` (default GET),
   * `port` (default 3000), `body` (string, for POST/PUT), `headers`
   * (string map), `connectTimeout` / `readTimeout` ms (default 5000).
   * Resolves with `{ status: number, body: string }`.
   */
  callApi(call: PluginCall): void {
    const path: string = call.getString('path', '/api/hello');
    const method: string = call.getString('method', 'GET').toUpperCase();
    const port: number = call.getInt('port', 3000);
    const body: string = call.getString('body', '');
    const headersObj: Record<string, Object> | null = call.getObject('headers');
    const connectTimeout: number = call.getInt('connectTimeout', 5000);
    const readTimeout: number = call.getInt('readTimeout', 5000);
    const safePort: number = port > 0 && port < 65536 ? port : 3000;
    const url: string = `http://127.0.0.1:${safePort}${path}`;
    const req = http.createHttp();
    let httpMethod: http.RequestMethod = http.RequestMethod.GET;
    if (method === 'POST') {
      httpMethod = http.RequestMethod.POST;
    } else if (method === 'PUT') {
      httpMethod = http.RequestMethod.PUT;
    } else if (method === 'DELETE') {
      httpMethod = http.RequestMethod.DELETE;
    } else if (method === 'HEAD') {
      httpMethod = http.RequestMethod.HEAD;
    } else if (method === 'OPTIONS') {
      httpMethod = http.RequestMethod.OPTIONS;
    }
    const headerMap: Record<string, string> = {};
    if (headersObj !== null) {
      const keys: string[] = Object.keys(headersObj);
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i];
        const v: Object | undefined = headersObj[k];
        if (typeof v === 'string') {
          headerMap[k] = v as string;
        }
      }
    }
    req
      .request(url, {
        method: httpMethod,
        header: headerMap,
        extraData: body.length > 0 ? body : undefined,
        connectTimeout: connectTimeout,
        readTimeout: readTimeout,
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
