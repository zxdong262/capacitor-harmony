import { copy, pathExists, readFile, readJson, readdir, remove, stat, writeFile, ensureDir } from 'fs-extra';
import { basename, join } from 'path';
import type { HookEnv } from './env';
import { log, replaceJson5ArrayField, replaceJson5StringField, setStringResource, warn } from './util';

/** Sub-path of the generated project that holds ArkTS plugin implementations. */
const PLUGINS_DIR = 'entry/src/main/ets/capacitor/plugins';
/** Where the web app is copied inside the HAP. */
const WWW_DIR = 'entry/src/main/resources/rawfile/www';
const NODE_DIR = 'entry/src/main/resources/rawfile/node';

function platformPath(env: HookEnv, ...parts: string[]): string {
  return join(env.rootDir, 'harmony', ...parts);
}

/**
 * Apply `appId` / `appName` (and the HarmonyOS overrides) to the generated
 * native project: bundle name, app label and the entry ability label.
 */
export async function applyAppIdentity(env: HookEnv): Promise<void> {
  const cfg = env.config;
  const harmony = cfg.harmony ?? {};
  const bundleName = harmony.bundleName || cfg.appId;
  const appLabel = harmony.appLabel || cfg.appName;

  if (!bundleName) {
    warn('no appId found in capacitor config — keeping the template bundleName');
  } else {
    const appJson = platformPath(env, 'AppScope', 'app.json5');
    if (!(await replaceJson5StringField(appJson, 'bundleName', bundleName))) {
      warn(`could not update bundleName in ${appJson}`);
    }
  }

  if (!appLabel) {
    return;
  }
  const scopeStrings = platformPath(env, 'AppScope', 'resources', 'base', 'element', 'string.json');
  await setStringResource(scopeStrings, 'app_name', appLabel);

  const moduleStrings = platformPath(env, 'entry', 'src', 'main', 'resources', 'base', 'element', 'string.json');
  await setStringResource(moduleStrings, 'EntryAbility_label', appLabel);
  await setStringResource(moduleStrings, 'app_name', appLabel);
}

/**
 * Write `rawfile/capacitor.config.json`.
 *
 * The ArkTS side reads this (through `resourceManager.getRawFileContentSync`)
 * so that changing `capacitor.config.ts` + `cap sync harmony` is enough —
 * no rebuild of the bridge constants needed.
 */
export async function writeRuntimeConfig(env: HookEnv): Promise<void> {
  const cfg = env.config;
  const harmony = cfg.harmony ?? {};
  // List the Node backend files so the runtime can unpack them into the
  // app's writable filesDir at launch. We embed this list directly in the
  // config (which is always written by `cap sync harmony`) rather than a
  // separate manifest file, so it can't get dropped by a partial sync.
  const nodeFiles = harmony.nodeDir === false ? [] : await listNodeFiles(join(env.rootDir, harmony.nodeDir || 'node'));
  const runtimeConfig = {
    appId: cfg.appId ?? '',
    appName: cfg.appName ?? '',
    // Local asset server unless the user points us somewhere else (typically
    // the Node backend, or a dev server during development).
    serverUrl: harmony.serverUrl || cfg.server?.url || 'http://localhost/',
    node: {
      enable: harmony.nodeDir !== false,
      entry: harmony.nodeEntry || 'main.js',
      autostart: harmony.autostartNode !== false,
      files: nodeFiles,
    },
    logging: {
      enabled: cfg.logging === true || (cfg as any).harmony?.logging === true,
    },
  };
  const file = platformPath(env, 'entry', 'src', 'main', 'resources', 'rawfile', 'capacitor.config.json');
  await writeFile(file, `${JSON.stringify(runtimeConfig, null, 2)}\n`);
  log('wrote rawfile/capacitor.config.json');
}

/**
 * Walk a directory and return relative file paths (skipping dotfiles), so the
 * runtime knows which files to unpack from rawfile into its writable dir.
 */
async function listNodeFiles(dir: string): Promise<string[]> {
  const out: string[] = [];
  const walk = async (sub: string): Promise<void> => {
    let entries: string[] = [];
    try {
      entries = await readdir(sub.length ? join(dir, sub) : dir);
    } catch (e) {
      return;
    }
    for (const name of entries.sort()) {
      if (name.startsWith('.')) {
        continue;
      }
      const rel = sub.length ? `${sub}/${name}` : name;
      const st = await stat(join(dir, rel));
      if (st.isDirectory()) {
        await walk(rel);
      } else {
        out.push(rel);
      }
    }
  };
  await walk('');
  return out;
}

/** Apply `harmony.deviceTypes` / `harmony.permissions` to `module.json5`. */
export async function applyModuleOverrides(env: HookEnv): Promise<void> {
  const harmony = env.config.harmony ?? {};
  const moduleJson = platformPath(env, 'entry', 'src', 'main', 'module.json5');
  if (harmony.deviceTypes?.length) {
    if (!(await replaceJson5ArrayField(moduleJson, 'deviceTypes', harmony.deviceTypes))) {
      warn(`could not update deviceTypes in ${moduleJson}`);
    }
  }
  if (harmony.permissions?.length && (await pathExists(moduleJson))) {
    const original = await readFile(moduleJson, 'utf8');
    const blocks = harmony.permissions
      .map(
        (p) => `    {\n      "name": "${p}",\n      "reason": "$string:reason",\n      "usedScene": {\n        "abilities": [\n          "EntryAbility"\n        ],\n        "when": "always"\n      }\n    }`,
      )
      .join(',\n');
    // Insert before the closing `],` of requestPermissions when it exists,
    // otherwise create the section right after `"module": {`.
    let next = original;
    const rp = /("requestPermissions"\s*:\s*\[)/;
    if (rp.test(original)) {
      next = original.replace(rp, `$1\n${blocks},`);
    }
    if (next !== original) {
      await writeFile(moduleJson, next);
    }
  }
}

interface DiscoveredPlugin {
  /** Capacitor plugin id (e.g. `App`). */
  id: string;
  /** ArkTS class name to instantiate. */
  className: string;
  /** Import specifier relative to `entry/src/main/ets/capacitor/`. */
  importPath: string;
}

/**
 * Collect every plugin that should end up in `PluginRegistry.ets`:
 *
 * 1. The plugins bundled with `capacitor-harmony` (already present in
 *    `entry/src/main/ets/capacitor/plugins/`) — file `Foo.ets` must export
 *    `FooPlugin`.
 * 2. Third-party plugins that declare a `capacitor.harmony` entry in their
 *    `package.json`.  Their `.ets` source is copied in during `update`.
 */
async function discoverPlugins(env: HookEnv): Promise<DiscoveredPlugin[]> {
  const plugins: DiscoveredPlugin[] = [];
  const seen = new Set<string>();
  const dir = platformPath(env, PLUGINS_DIR);

  // 1. bundled / already copied plugins
  const { readdir } = await import('fs-extra');
  if (await pathExists(dir)) {
    const files = (await readdir(dir)).filter((f) => f.endsWith('.ets')).sort();
    for (const file of files) {
      const id = basename(file, '.ets');
      if (seen.has(id)) {
        continue;
      }
      seen.add(id);
      plugins.push({ id, className: `${id}Plugin`, importPath: `./plugins/${id}` });
    }
  }

  // 2. third-party packages
  const pkgPath = join(env.rootDir, 'package.json');
  if (await pathExists(pkgPath)) {
    const pkg = await readJson(pkgPath);
    const deps = { ...(pkg.dependencies ?? {}), ...(pkg.devDependencies ?? {}) };
    for (const depName of Object.keys(deps)) {
      const depPkgPath = join(env.rootDir, 'node_modules', depName, 'package.json');
      if (!(await pathExists(depPkgPath))) {
        continue;
      }
      let depPkg: any;
      try {
        depPkg = await readJson(depPkgPath);
      } catch {
        continue;
      }
      const meta = depPkg?.capacitor?.harmony;
      if (!meta?.src) {
        continue;
      }
      const id: string = meta.id || basename(String(meta.src), '.ets');
      if (seen.has(id)) {
        continue;
      }
      seen.add(id);
      plugins.push({
        id,
        className: meta.className || `${id}Plugin`,
        importPath: `./plugins/${id}`,
      });
    }
  }

  return plugins;
}

/**
 * Copy third-party plugin sources declared via `capacitor.harmony` into the
 * generated project.
 */
export async function syncThirdPartyPluginSources(env: HookEnv): Promise<void> {
  const pkgPath = join(env.rootDir, 'package.json');
  if (!(await pathExists(pkgPath))) {
    return;
  }
  const pkg = await readJson(pkgPath);
  const deps = { ...(pkg.dependencies ?? {}), ...(pkg.devDependencies ?? {}) };
  const destDir = platformPath(env, PLUGINS_DIR);
  await ensureDir(destDir);

  for (const depName of Object.keys(deps)) {
    const depRoot = join(env.rootDir, 'node_modules', depName);
    const depPkgPath = join(depRoot, 'package.json');
    if (!(await pathExists(depPkgPath))) {
      continue;
    }
    let depPkg: any;
    try {
      depPkg = await readJson(depPkgPath);
    } catch {
      continue;
    }
    const meta = depPkg?.capacitor?.harmony;
    if (!meta?.src) {
      continue;
    }
    const src = join(depRoot, String(meta.src));
    if (!(await pathExists(src))) {
      warn(`plugin ${depName}: harmony source not found at ${src}`);
      continue;
    }
    const destName = `${meta.id || basename(String(meta.src), '.ets')}.ets`;
    await copy(src, join(destDir, destName));
    log(`plugin ${depName} → plugins/${destName}`);
  }
}

/**
 * (Re)generate `PluginRegistry.ets`.
 *
 * The registry is the single place that maps a Capacitor plugin id to an
 * ArkTS implementation, and it is what produces the `Capacitor.PluginHeaders`
 * array injected into the WebView.
 */
export async function generatePluginRegistry(env: HookEnv): Promise<void> {
  const plugins = await discoverPlugins(env);
  const imports = plugins.map((p) => `import { ${p.className} } from '${p.importPath}';`).join('\n');
  const registrations = plugins
    .map((p) => `    this.plugins.set('${p.id}', new ${p.className}(this.bridge, this.context));`)
    .join('\n');

  const content = `/**
 * PluginRegistry.ets — GENERATED by capacitor-harmony. DO NOT EDIT.
 *
 * Regenerate with:  npx cap sync harmony
 *
 * Every plugin registered here is exposed to the WebView through
 * \`Capacitor.PluginHeaders\`, which is what makes \`registerPlugin()\` route
 * calls to the native side.
 */

import { common } from '@kit.AbilityKit';
import { PluginHost } from './BridgeInterfaces';
import { CapacitorPlugin } from './CapacitorPlugin';
${imports}

export function registerPlugins(host: PluginHost): void {
  const context: common.UIAbilityContext = host.getContext();
  const plugins: CapacitorPlugin[] = [
${plugins.map((p) => `    new ${p.className}(host, context),`).join('\n')}
  ];
  plugins.forEach((plugin: CapacitorPlugin) => {
    host.registerPlugin(plugin);
  });
}
`;

  const file = platformPath(env, 'entry', 'src', 'main', 'ets', 'capacitor', 'PluginRegistry.ets');
  await writeFile(file, content);
  log(`PluginRegistry.ets generated (${plugins.length} plugins)`);
}

export { WWW_DIR, NODE_DIR, PLUGINS_DIR, platformPath };

/** Remove a directory if it exists. */
export async function removeIfExists(dir: string): Promise<void> {
  if (await pathExists(dir)) {
    await remove(dir);
  }
}
