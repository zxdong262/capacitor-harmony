import type { PluginListenerHandle } from '@capacitor/core';
import type { NodePlugin, NodeStartResult, NodeStatus, NodeInfo } from './definitions';

/**
 * Web (non-HarmonyOS) fallback for the Node runtime.
 *
 * There is no embedded Node on the web, so the controls resolve to a "not
 * running" state and the listeners never fire.  Application code that uses
 * `startNode()` etc. inside a `Capacitor.getPlatform() === 'harmony'` guard,
 * or that talks to a dev server instead, keeps working everywhere.
 */
export class NodeWeb implements NodePlugin {
  start(): Promise<NodeStartResult> {
    return Promise.resolve({ running: false });
  }

  stop(): Promise<NodeStatus> {
    return Promise.resolve({ running: false });
  }

  getStatus(): Promise<NodeStatus> {
    return Promise.resolve({ running: false });
  }

  getInfo(): Promise<NodeInfo> {
    return Promise.resolve({ entry: '', entryPath: '', dir: '' });
  }

  addListener(): Promise<PluginListenerHandle> {
    return Promise.resolve({ remove: () => Promise.resolve() });
  }
}
