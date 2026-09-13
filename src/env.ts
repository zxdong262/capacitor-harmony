import { join, resolve } from 'path';
import type { CapacitorConfig } from './types';

/**
 * The Capacitor CLI spawns the `capacitor:*` hooks with these env vars set
 * (see `runPlatformHook()` in `@capacitor/cli`).
 */
export interface HookEnv {
  /** Absolute path of the Capacitor app root (where capacitor.config.* lives). */
  rootDir: string;
  /** Absolute path of the built web assets. */
  webDir: string;
  /** The raw external config. */
  config: CapacitorConfig;
  /** Platform name the hook was invoked with (always `harmony` for us). */
  platformName: string;
  /** Directory of the installed `capacitor-harmony` package. */
  packageDir: string;
}

function parseConfig(raw: string | undefined): CapacitorConfig {
  if (!raw) {
    return {};
  }
  try {
    return JSON.parse(raw) as CapacitorConfig;
  } catch (e) {
    console.warn(`[capacitor-harmony] could not parse CAPACITOR_CONFIG: ${String(e)}`);
    return {};
  }
}

export function readHookEnv(cliConfig?: CapacitorConfig): HookEnv {
  const rootDir = process.env.CAPACITOR_ROOT_DIR
    ? resolve(process.env.CAPACITOR_ROOT_DIR)
    : process.cwd();

  const webDir = process.env.CAPACITOR_WEB_DIR
    ? resolve(process.env.CAPACITOR_WEB_DIR)
    : join(rootDir, (cliConfig?.webDir as string) || (parseConfig(process.env.CAPACITOR_CONFIG).webDir as string) || 'dist');

  // The hook is spawned with cwd = the installed package dir, so __dirname/..
  // is the package root.  Fall back to walking up from __dirname for the
  // not-yet-published (linked / monorepo) case.
  const packageDir = resolve(__dirname, '..');

  return {
    rootDir,
    webDir,
    config: cliConfig && Object.keys(cliConfig).length > 0 ? cliConfig : parseConfig(process.env.CAPACITOR_CONFIG),
    platformName: process.env.CAPACITOR_PLATFORM_NAME || 'harmony',
    packageDir,
  };
}

/** Name of the generated native project directory. */
export const PLATFORM_DIR_NAME = 'harmony';
