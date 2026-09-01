import { Capacitor, PluginListenerHandle } from '@capacitor/core';
import type { NodePlugin } from './definitions';

/**
 * The embedded Node.js runtime, controlled from the web app.
 *
 * On HarmonyOS these calls talk to the `Node` native plugin, which boots the
 * real `libnode.so` runtime and runs the entry file under `rawfile/node/`.
 * On every other platform the same API is available with a no-op web fallback,
 * so application code can stay platform-agnostic.
 */
export const Node = Capacitor.registerPlugin<NodePlugin>('Node', {
  web: async () => new (await import('./web')).NodeWeb(),
});

export function startNode(): Promise<{ running: boolean }> {
  return Node.start();
}

export function stopNode(): Promise<{ running: boolean }> {
  return Node.stop();
}

export function getNodeStatus(): Promise<{ running: boolean }> {
  return Node.getStatus();
}

export function getNodeInfo(): Promise<{ entry: string; entryPath: string; dir: string }> {
  return Node.getInfo();
}

/** Stream of the Node process's stdout. */
export function onNodeStdout(callback: (event: { line: string }) => void): Promise<PluginListenerHandle> {
  return Node.addListener('stdout', callback as (event: any) => void);
}

/** Stream of the Node process's stderr. */
export function onNodeStderr(callback: (event: { line: string }) => void): Promise<PluginListenerHandle> {
  return Node.addListener('stderr', callback as (event: any) => void);
}

/** Fired once when the Node process exits. */
export function onNodeExit(callback: (event: { code: number }) => void): Promise<PluginListenerHandle> {
  return Node.addListener('exit', callback as (event: any) => void);
}

/**
 * Convenience: call an HTTP route served by the Node backend.
 *
 * The backend binds to `127.0.0.1` on the given port (default 3000). Use this
 * to bridge the WebView to your Node server without exposing it to the network.
 */
export function nodeFetch(path: string, port = 3000, init?: RequestInit): Promise<Response> {
  const url = `http://127.0.0.1:${port}${path}`;
  return fetch(url, init);
}

export * from './definitions';
