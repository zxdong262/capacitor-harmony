import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { start, stop, isRunning, setOutputListener, setExitListener } from 'libcapacitor_node.so';

const TAG: string = 'NodeRuntime';
const DOMAIN: number = 0x0000;

/** A line of output produced by the embedded Node.js process. */
export type NodeOutputHandler = (level: string, line: string) => void;
export type NodeExitHandler = (code: number) => void;

/**
 * Thin ArkTS wrapper around the embedded Node.js runtime.
 *
 * The actual runtime lives in `libcapacitor_node.so` (see
 * `entry/src/main/cpp/capacitor_node`), a small NAPI module that `dlopen()`s
 * the prebuilt `libnode.so` shipped by
 * [ohos-node-shared](https://github.com/electerm/ohos-node-shared) and runs the
 * app's entry file on a dedicated thread.
 *
 * The NAPI module is always linked into the app, so importing it is safe even
 * when `libnode.so` has not been downloaded yet — `start()` simply fails with a
 * descriptive error in that case.
 */
export class NodeRuntime {
  private context: common.UIAbilityContext;
  private dir: string = '';
  private entry: string = 'main.js';
  private running: boolean = false;
  private lastError: string = '';
  private outputHandlers: NodeOutputHandler[] = [];
  private exitHandlers: NodeExitHandler[] = [];
  private wired: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  /** Where `rawfile/node/**` gets unpacked, and Node's working directory. */
  configure(dir: string, entry: string): void {
    this.dir = dir;
    this.entry = entry;
  }

  getDir(): string {
    return this.dir;
  }

  getEntry(): string {
    return this.entry;
  }

  getEntryPath(): string {
    return `${this.dir}/${this.entry}`;
  }

  getLastError(): string {
    return this.lastError;
  }

  isRunning(): boolean {
    return this.running;
  }

  onOutput(handler: NodeOutputHandler): void {
    this.outputHandlers.push(handler);
  }

  onExit(handler: NodeExitHandler): void {
    this.exitHandlers.push(handler);
  }

  /** Register the native callbacks once. Must run before the first `start()`. */
  private wire(): void {
    if (this.wired) {
      return;
    }
    this.wired = true;
    try {
      setOutputListener((level: string, line: string): void => {
        this.emitOutput(level, line);
      });
      setExitListener((code: number): void => {
        this.running = false;
        hilog.info(DOMAIN, TAG, 'node exited with code %{public}d', code);
        this.exitHandlers.forEach((handler: NodeExitHandler) => {
          handler(code);
        });
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'failed to install node listeners: %{public}s', String(e));
    }
  }

  private emitOutput(level: string, line: string): void {
    if (level === 'error') {
      hilog.error(DOMAIN, TAG, '%{public}s', line);
    } else {
      hilog.info(DOMAIN, TAG, '%{public}s', line);
    }
    this.outputHandlers.forEach((handler: NodeOutputHandler) => {
      handler(level, line);
    });
  }

  /**
   * Boot Node on its own thread.
   *
   * The entry file is expected to do the usual thing — start an HTTP server on
   * localhost and let the WebView talk to it with `fetch()`.
   */
  start(): boolean {
    if (this.running) {
      return true;
    }
    if (this.dir.length === 0) {
      this.lastError = 'node runtime is not configured';
      return false;
    }
    this.wire();
    try {
      const ok: boolean = start(this.getEntryPath(), this.dir);
      this.running = ok;
      if (!ok) {
        this.lastError = 'failed to start node — is libnode.so present in entry/libs/<abi>?';
        hilog.error(DOMAIN, TAG, '%{public}s', this.lastError);
      }
      return ok;
    } catch (e) {
      this.lastError = String(e);
      hilog.error(DOMAIN, TAG, 'start failed: %{public}s', this.lastError);
      return false;
    }
  }

  stop(): void {
    if (!this.running) {
      return;
    }
    try {
      stop();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'stop failed: %{public}s', String(e));
    }
    this.running = false;
  }

  /** Ask the native side (survives an app restart mid-run). */
  refreshStatus(): boolean {
    try {
      this.running = isRunning();
    } catch (e) {
      this.running = false;
    }
    return this.running;
  }
}
