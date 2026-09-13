import { readHookEnv } from './env';
import type { CapacitorConfig } from './types';
import { add as addImpl } from './add';
import { copy as copyImpl } from './copy';
import { update as updateImpl } from './update';
import { open as openImpl } from './open';

export type { CapacitorConfig, HarmonyPlatformConfig } from './types';
export type { HookEnv } from './env';

/**
 * Capacitor CLI hooks.
 *
 * `@capacitor/cli` resolves the platform package for
 * `cap <add|copy|update|open> harmony`, then runs the matching `capacitor:*`
 * npm script from that package with `CAPACITOR_CONFIG`, `CAPACITOR_ROOT_DIR`
 * and `CAPACITOR_WEB_DIR` in the environment.  Some CLI versions also pass the
 * config object directly — we prefer it when it is non-empty and otherwise
 * fall back to the environment.
 */

export async function add(config?: CapacitorConfig): Promise<void> {
  await addImpl(readHookEnv(config));
}

export async function copy(config?: CapacitorConfig): Promise<void> {
  await copyImpl(readHookEnv(config));
}

export async function update(config?: CapacitorConfig): Promise<void> {
  await updateImpl(readHookEnv(config));
}

export async function open(config?: CapacitorConfig): Promise<void> {
  await openImpl(readHookEnv(config));
}

/** Convenience: `copy` + `update`, matching `cap sync harmony`. */
export async function sync(config?: CapacitorConfig): Promise<void> {
  await copy(config);
  await update(config);
}
