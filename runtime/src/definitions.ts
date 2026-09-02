import type { PluginListenerHandle } from '@capacitor/core';

export interface NodeStartResult {
  running: boolean;
  /** Empty on success; otherwise why the runtime could not be started. */
  error: string;
}

export interface NodeStatus {
  running: boolean;
  /** Last failure reason (native start error, crash signal, exit code, …). */
  error: string;
  /** Tail of the native boot log `<node dir>/node-boot.log`. */
  log: string;
}

export interface NodeLog {
  /** Tail of the native boot log `<node dir>/node-boot.log`. */
  log: string;
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
  getLog(): Promise<NodeLog>;
  addListener(eventName: string, listener: (event: any) => void): Promise<PluginListenerHandle>;
}
