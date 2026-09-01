import { common } from '@kit.AbilityKit';
import { PluginHost } from '../BridgeInterfaces';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';
import { NodeExitPayload, NodeInfoPayload, NodeLinePayload, NodeRunningPayload } from '../BridgeInterfaces';
import { NodeRuntime } from '../NodeRuntime';

/**
 * `capacitor-harmony/node` — control the embedded Node.js runtime from JS.
 *
 * The typical pattern is to boot a Node HTTP server in `main.js` and talk to it
 * from the WebView with `fetch('http://127.0.0.1:<port>/...')`.
 *
 * Methods: `start`, `stop`, `getStatus`, `getInfo`.
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
    return ['start', 'stop', 'getStatus', 'getInfo'];
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
}
