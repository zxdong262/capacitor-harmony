import type { PluginListenerHandle } from '@capacitor/core';

export interface NodeStartResult {
  running: boolean;
}

export interface NodeStatus {
  running: boolean;
}

export interface NodeInfo {
  entry: string;
  entryPath: string;
  dir: string;
}

/**
 * The native interface exposed by the `Node` Capacitor plugin on HarmonyOS.
 * It is the contract that `index.ts` binds to via `registerPlugin`.  `any` on
 * the listener keeps the event shape flexible across `stdout`/`stderr`/`exit`.
 */
export interface NodePlugin {
  start(): Promise<NodeStartResult>;
  stop(): Promise<NodeStatus>;
  getStatus(): Promise<NodeStatus>;
  getInfo(): Promise<NodeInfo>;
  addListener(eventName: string, listener: (event: any) => void): Promise<PluginListenerHandle>;
}
