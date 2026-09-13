import { common } from '@kit.AbilityKit';
import { PluginHost } from './BridgeInterfaces';
import { PluginCall } from './PluginCall';

/**
 * Base class for every native Capacitor plugin on HarmonyOS.
 *
 * Subclasses declare their Capacitor plugin id plus the list of method names
 * they implement:
 *
 * ```ts
 * export class EchoPlugin extends CapacitorPlugin {
 *   getPluginId(): string { return 'Echo'; }
 *   getMethods(): string[] { return ['echo']; }
 *   echo(call: PluginCall): void { call.resolve({ value: call.getString('value') }); }
 * }
 * ```
 *
 * Methods are dispatched by name (see `PluginRegistry`), and every name in
 * `getMethods()` ends up in `Capacitor.PluginHeaders` so `@capacitor/core`
 * routes the call to native instead of the web fallback.
 */
export abstract class CapacitorPlugin {
  protected bridge: PluginHost;
  protected context: common.UIAbilityContext;

  /** eventName -> callbackIds of registered listeners. */
  private listeners: Map<string, string[]> = new Map();
  /** eventName -> callbackId of the PluginCall that registered it. */
  private listenerCalls: Map<string, PluginCall> = new Map();
  /** Events fired before anyone listened, replayed on the first listener. */
  private retainedEvents: Map<string, Object[]> = new Map();

  constructor(bridge: PluginHost, context: common.UIAbilityContext) {
    this.bridge = bridge;
    this.context = context;
  }

  /** Hook called once, right after registration. Optional. */
  load(): void {}

  /** The Capacitor plugin id, e.g. `App`. */
  abstract getPluginId(): string;

  /** Method names implemented natively. Include `addListener`/`removeListener` only if overridden. */
  abstract getMethods(): string[];

  /**
   * Register a JS listener.
   *
   * The call is kept alive so that resolving it later delivers an event while
   * leaving the callback registered (`save: true`).
   */
  addListener(call: PluginCall): void {
    const eventName: string = call.getString('eventName');
    if (eventName.length === 0) {
      call.reject('eventName is required');
      return;
    }
    const ids: string[] = this.listeners.get(eventName) ?? [];
    if (ids.length === 0) {
      ids.push(call.callbackId);
      this.listeners.set(eventName, ids);
      this.listenerCalls.set(call.callbackId, call);
      call.resolve();
      this.sendRetainedEvents(eventName);
      return;
    }
    ids.push(call.callbackId);
    this.listenerCalls.set(call.callbackId, call);
    call.resolve();
  }

  removeListener(call: PluginCall): void {
    const eventName: string = call.getString('eventName');
    const callbackId: string = call.getString('callbackId');
    if (callbackId.length > 0) {
      this.dropListener(eventName, callbackId);
    } else {
      this.listeners.set(eventName, []);
    }
    call.resolve();
  }

  removeAllListeners(call: PluginCall): void {
    this.listeners = new Map();
    this.listenerCalls = new Map();
    call.resolve();
  }

  hasListeners(eventName: string): boolean {
    const ids: string[] = this.listeners.get(eventName) ?? [];
    return ids.length > 0;
  }

  /**
   * Deliver an event to every registered listener.
   *
   * @param retainUntilConsumed replay the event for the first listener when
   *   nobody is listening yet (used for one-shot launch events such as
   *   `appUrlOpen`).
   */
  notifyListeners(eventName: string, data: Object, retainUntilConsumed: boolean = false): void {
    const ids: string[] = this.listeners.get(eventName) ?? [];
    if (ids.length === 0) {
      if (retainUntilConsumed) {
        const pending: Object[] = this.retainedEvents.get(eventName) ?? [];
        pending.push(data);
        this.retainedEvents.set(eventName, pending);
      }
      return;
    }
    // Snapshot: a listener may remove itself while we iterate.
    const snapshot: string[] = ids.slice();
    snapshot.forEach((callbackId: string) => {
      this.bridge.sendResult(callbackId, data, true, true);
    });
  }

  private sendRetainedEvents(eventName: string): void {
    const pending: Object[] = this.retainedEvents.get(eventName) ?? [];
    if (pending.length === 0) {
      return;
    }
    this.retainedEvents.delete(eventName);
    pending.forEach((data: Object) => this.notifyListeners(eventName, data));
  }

  private dropListener(eventName: string, callbackId: string): void {
    const ids: string[] = this.listeners.get(eventName) ?? [];
    const next: string[] = ids.filter((id: string) => id !== callbackId);
    this.listeners.set(eventName, next);
    this.listenerCalls.delete(callbackId);
  }
}
