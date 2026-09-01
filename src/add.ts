import { copy, pathExists, ensureDir, writeFile } from 'fs-extra';
import { join } from 'path';
import type { HookEnv } from './env';
import {
  NODE_DIR,
  PLUGINS_DIR,
  WWW_DIR,
  applyAppIdentity,
  applyModuleOverrides,
  generatePluginRegistry,
  platformPath,
  syncThirdPartyPluginSources,
  writeRuntimeConfig,
} from './configure';
import { log, warn } from './util';

const TEMPLATE_DIR = join(__dirname, '..', 'assets', 'native-template');
const NODE_RUNTIME_DIR = join(__dirname, '..', 'native', 'node-runtime');
const SCRIPTS_DIR = join(__dirname, '..', 'scripts');

/**
 * `npx cap add harmony`
 *
 * Copies the HarmonyOS native template into `<rootDir>/harmony`, drops in the
 * C++ Node.js glue, the helper scripts, and then applies the app identity +
 * plugin registry.  Idempotent: refuses to clobber an existing project.
 */
export async function add(env: HookEnv): Promise<void> {
  const platformDir = join(env.rootDir, 'harmony');

  if (await pathExists(platformDir)) {
    warn(`${platformDir} already exists — skipping. Delete it to start over.`);
    return;
  }

  if (!(await pathExists(TEMPLATE_DIR))) {
    throw new Error(`native template not found at ${TEMPLATE_DIR} (is capacitor-harmony installed correctly?)`);
  }

  log('adding HarmonyOS platform…');
  await copy(TEMPLATE_DIR, platformDir);

  // C++ glue for the embedded Node.js runtime (libnode.so).
  if (await pathExists(NODE_RUNTIME_DIR)) {
    await copy(NODE_RUNTIME_DIR, platformPath(env, 'entry', 'src', 'main', 'cpp', 'capacitor_node'));
    log('copied native/node-runtime → entry/src/main/cpp/capacitor_node');
  }

  // Helper scripts (prepare-node.sh, build-hap.sh, …).
  if (await pathExists(SCRIPTS_DIR)) {
    await copy(SCRIPTS_DIR, platformPath(env, 'scripts'));
    await makeExecutable(platformPath(env, 'scripts'));
    log('copied scripts/ → harmony/scripts');
  }

  for (const dir of [WWW_DIR, NODE_DIR, PLUGINS_DIR]) {
    await ensureDir(platformPath(env, dir));
  }
  await writeFile(
    platformPath(env, WWW_DIR, 'index.html'),
    [
      '<!doctype html>',
      '<html><head><meta charset="utf-8" /><title>Capacitor HarmonyOS</title></head>',
      '<body><h1>Run <code>npm run build &amp;&amp; npx cap sync harmony</code></h1></body></html>',
      '',
    ].join('\n'),
  );

  await applyAppIdentity(env);
  await applyModuleOverrides(env);
  await syncThirdPartyPluginSources(env);
  await generatePluginRegistry(env);
  await writeRuntimeConfig(env);

  log('');
  log('HarmonyOS platform added.');
  log('  next:  ./harmony/scripts/prepare-node.sh arm64   # download libnode.so (~121 MB)');
  log('         npx cap sync harmony');
  log('         ./harmony/scripts/build-hap.sh');
}

async function makeExecutable(dir: string): Promise<void> {
  const { chmod, readdir } = await import('fs-extra');
  const { join: p } = await import('path');
  const entries = await readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.isFile() && entry.name.endsWith('.sh')) {
      await chmod(p(dir, entry.name), 0o755);
    }
  }
}
