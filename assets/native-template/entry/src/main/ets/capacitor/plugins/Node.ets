import { common } from '@kit.AbilityKit';
import { PluginHost } from '../BridgeInterfaces';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';
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
      this.notifyListeners(level === 'error' ? 'stderr' : 'stdout', { line: line } as Object);
    });
    this.node.onExit((code: number) => {
      this.notifyListeners('exit', { code: code } as Object);
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
      call.resolve({ running: true } as Object);
    } else {
      call.reject(this.node.getLastError() || 'node failed to start', 'START_FAILED');
    }
  }

  stop(call: PluginCall): void {
    this.node.stop();
    call.resolve({ running: false } as Object);
  }

  getStatus(call: PluginCall): void {
    call.resolve({ running: this.node.isRunning() } as Object);
  }

  getInfo(call: PluginCall): void {
    call.resolve({
      entry: this.node.getEntry(),
      entryPath: this.node.getEntryPath(),
      dir: this.node.getDir(),
    } as Object);
  }
}
