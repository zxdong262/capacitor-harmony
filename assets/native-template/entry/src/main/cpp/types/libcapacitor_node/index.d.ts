/**
 * Type declarations for the embedded Node.js runtime (`libcapacitor_node.so`).
 *
 * The actual implementation lives in `native/node-runtime/capacitor_node.cpp`
 * and links the prebuilt shared `libnode.so` from ohos-node-shared.
 */
export const start: (entryPath: string, dataDir: string) => boolean;
export const stop: () => void;
export const isRunning: () => boolean;
export const setOutputListener: (listener: (level: string, line: string) => void) => void;
export const setExitListener: (listener: (code: number) => void) => void;
