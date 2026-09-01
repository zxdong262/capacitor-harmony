import { copy as fsCopy, emptyDir, ensureDir, pathExists } from 'fs-extra';
import { join } from 'path';
import type { HookEnv } from './env';
import { NODE_DIR, WWW_DIR, platformPath, writeRuntimeConfig } from './configure';
import { log, warn } from './util';

/**
 * `npx cap copy harmony`
 *
 * Copies the built web assets into the HAP's `rawfile/www` and — when
 * configured — the Node.js backend into `rawfile/node`.
 */
export async function copyWebAssets(env: HookEnv): Promise<void> {
  const platformDir = join(env.rootDir, 'harmony');
  if (!(await pathExists(platformDir))) {
    throw new Error(`HarmonyOS platform not found at ${platformDir}. Run: npx cap add harmony`);
  }

  // ---- web assets ---------------------------------------------------------
  const src = env.webDir;
  const dest = platformPath(env, WWW_DIR);
  if (!(await pathExists(src))) {
    throw new Error(`web assets directory not found: ${src}. Did you build your web app?`);
  }
  if (!(await pathExists(join(src, 'index.html')))) {
    throw new Error(`${src} must contain an index.html`);
  }
  await emptyDir(dest);
  await fsCopy(src, dest);
  log(`web assets → harmony/${WWW_DIR}`);

  // ---- node backend -------------------------------------------------------
  const harmony = env.config.harmony ?? {};
  const nodeDest = platformPath(env, NODE_DIR);
  await emptyDir(nodeDest);

  if (harmony.nodeDir === false) {
    log('node backend disabled (harmony.nodeDir === false)');
  } else {
    const nodeDir = harmony.nodeDir || 'node';
    const nodeSrc = join(env.rootDir, nodeDir);
    if (await pathExists(nodeSrc)) {
      await fsCopy(nodeSrc, nodeDest);
      const entryPath = join(nodeDest, harmony.nodeEntry || 'main.js');
      if (await pathExists(entryPath)) {
        log(`node backend → harmony/${NODE_DIR} (entry: ${harmony.nodeEntry || 'main.js'})`);
      } else {
        warn(`node backend copied but entry "${harmony.nodeEntry || 'main.js'}" is missing — Node will not start`);
      }
    } else {
      warn(`no node backend at ${nodeSrc} — set \`harmony.nodeDir\` or create the directory`);
    }
  }

  await writeRuntimeConfig(env);
}

/** Alias used by `cap sync harmony` (which runs copy then update). */
export const copy = copyWebAssets;

/** Exported so `update` can re-create dirs that `cap add` normally makes. */
export { ensureDir };
