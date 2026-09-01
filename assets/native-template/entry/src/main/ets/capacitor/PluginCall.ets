import { PluginErrorData, PluginHost } from './BridgeInterfaces';

/**
 * The payload shape plugins hand to `resolve()` / `notifyListeners()`.
 *
 * ArkTS rejects object literals that do not "correspond to some explicitly
 * declared class or interface" (arkts-no-untyped-obj-literals).  Neither
 * `{...} as Object` nor `Record<string, Object>` satisfies that rule, but a
 * named interface does — and the index signature keeps the keys free-form so
 * every plugin can build its own result object.
 */
export interface PluginData {
  [key: string]: Object | null;
}

/**
 * A single plugin method invocation coming from the WebView.
 *
 * Mirrors `com.getcapacitor.PluginCall` / `CAPPluginCall`: read the arguments
 * with the typed getters, then finish with `resolve()` or `reject()`.
 */
export class PluginCall {
  pluginId: string;
  methodName: string;
  callbackId: string;
  options: Record<string, Object>;
  private host: PluginHost;
  private keepAlive: boolean = false;
  private finished: boolean = false;

  constructor(
    host: PluginHost,
    pluginId: string,
    methodName: string,
    callbackId: string,
    options: Record<string, Object>,
  ) {
    this.host = host;
    this.pluginId = pluginId;
    this.methodName = methodName;
    this.callbackId = callbackId;
    this.options = options ?? {};
  }

  getString(key: string, fallback: string = ''): string {
    const value = this.options[key];
    if (typeof value === 'string') {
      return value;
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return String(value);
    }
    return fallback;
  }

  getBoolean(key: string, fallback: boolean = false): boolean {
    const value = this.options[key];
    if (typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'string') {
      return value === 'true' || value === '1';
    }
    return fallback;
  }

  getNumber(key: string, fallback: number = 0): number {
    const value = this.options[key];
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = parseFloat(value);
      return isNaN(parsed) ? fallback : parsed;
    }
    return fallback;
  }

  getObject(key: string): Record<string, Object> | null {
    const value = this.options[key];
    if (typeof value === 'object' && value !== null) {
      return value as Record<string, Object>;
    }
    return null;
  }

  getArray(key: string): Object[] {
    const value = this.options[key];
    if (Array.isArray(value)) {
      return value as Object[];
    }
    return [];
  }

  getInt(key: string, fallback: number = 0): number {
    return Math.trunc(this.getNumber(key, fallback));
  }

  has(key: string): boolean {
    return this.options[key] !== undefined && this.options[key] !== null;
  }

  /**
   * Keep the callback alive after `resolve()` so it can be invoked again.
   * Required for `addListener` — see CapacitorPlugin.notifyListeners().
   */
  setKeepAlive(keepAlive: boolean): void {
    this.keepAlive = keepAlive;
  }

  isKeptAlive(): boolean {
    return this.keepAlive;
  }

  isFinished(): boolean {
    return this.finished;
  }

  resolve(data?: Object): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    this.host.sendResult(this.callbackId, data ?? ({} as Record<string, Object>), true, this.keepAlive);
  }

  /** Resolve with `save: true` so the JS callback stays registered. */
  resolveKeepAlive(data?: Object): void {
    this.keepAlive = true;
    this.finished = true;
    this.host.sendResult(this.callbackId, data ?? ({} as Record<string, Object>), true, true);
  }

  reject(message: string, code?: string, error?: Object): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    const errData: PluginErrorData = { message: message };
    if (code !== undefined) {
      errData.code = code;
    }
    if (error !== undefined) {
      errData.error = error;
    }
    this.host.sendResult(this.callbackId, errData as Object, false, false);
  }

  unavailable(message: string = 'not available'): void {
    this.reject(message, 'UNAVAILABLE');
  }

  unimplemented(message: string = 'not implemented'): void {
    this.reject(message, 'UNIMPLEMENTED');
  }
}
