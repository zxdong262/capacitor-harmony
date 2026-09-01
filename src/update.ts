import { pathExists } from 'fs-extra';
import { join } from 'path';
import type { HookEnv } from './env';
import {
  applyAppIdentity,
  applyModuleOverrides,
  generatePluginRegistry,
  syncThirdPartyPluginSources,
  writeRuntimeConfig,
} from './configure';
import { log, warn } from './util';

/**
 * `npx cap update harmony`
 *
 * Re-applies everything derived from `capacitor.config.*` to the native
 * project: bundle name / labels, `module.json5` overrides, third-party plugin
 * sources, the generated `PluginRegistry.ets` and the runtime config consumed
 * by the ArkTS bridge.
 */
export async function update(env: HookEnv): Promise<void> {
  const platformDir = join(env.rootDir, 'harmony');
  if (!(await pathExists(platformDir))) {
    throw new Error(`HarmonyOS platform not found at ${platformDir}. Run: npx cap add harmony`);
  }

  await applyAppIdentity(env);
  await applyModuleOverrides(env);
  await syncThirdPartyPluginSources(env);
  await generatePluginRegistry(env);
  await writeRuntimeConfig(env);

  log('HarmonyOS platform updated.');
  warn('remember to re-run ./harmony/scripts/prepare-node.sh if you bumped the Node version');
}
