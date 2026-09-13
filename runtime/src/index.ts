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

export function startNode(): Promise<{ running: boolean; error: string }> {
  return Node.start();
}

export function stopNode(): Promise<{ running: boolean; error: string }> {
  return Node.stop();
}

export function getNodeStatus(): Promise<{ running: boolean; error: string; log: string }> {
  return Node.getStatus();
}

export function getNodeInfo(): Promise<{ entry: string; entryPath: string; dir: string }> {
  return Node.getInfo();
}

/**
 * Tail of the native boot log.
 *
 * `libcapacitor_node.so` writes every boot step and every fatal signal here,
 * so this is the first thing to look at when the backend never comes up.
 */
export function getNodeLog(): Promise<{ log: string }> {
  return Node.getLog();
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
 * On HarmonyOS the WebView cannot open a socket to 127.0.0.1, so this goes
 * through the native `Node.callApi` proxy. Everywhere else it falls back to
 * a plain `fetch()` against the local dev server.
 */
export async function nodeFetch(path: string, port = 3000, init?: RequestInit): Promise<Response> {
  if (Capacitor.isNativePlatform()) {
    const method = init?.method ?? 'GET';
    let bodyText = '';
    if (typeof init?.body === 'string') {
      bodyText = init.body;
    }
    const headers: Record<string, string> = {};
    if (init?.headers) {
      const h = new Headers(init.headers);
      h.forEach((value, key) => {
        headers[key] = value;
      });
    }
    const r = await Node.callApi({ path, method, port, body: bodyText, headers });
    return new Response(r.body, { status: r.status });
  }
  const url = `http://127.0.0.1:${port}${path}`;
  return fetch(url, init);
}

/** Direct access to the native HTTP proxy (HarmonyOS only). */
export function nodeCallApi(options?: {
  path?: string;
  method?: string;
  port?: number;
  body?: string;
  headers?: Record<string, string>;
}): Promise<{ status: number; body: string }> {
  return Node.callApi(options);
}

export * from './definitions';
