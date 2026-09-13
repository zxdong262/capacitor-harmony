import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import { DEFAULT_RUNTIME_CONFIG, ExtractReport, RuntimeConfig } from './BridgeInterfaces';

const TAG: string = 'CapacitorConfig';
const DOMAIN: number = 0x0000;

const CONFIG_FILE: string = 'capacitor.config.json';
// NOT a dotfile: hvigor's rawfile packaging silently drops dotfiles, so a
// `.file-list.json` manifest would never reach the device.
const NODE_FILE_LIST: string = 'node/file-list.json';
/** Manifest file name — never extracted into the writable dir itself. */
const NODE_FILE_LIST_NAME: string = 'file-list.json';

function decodeUtf8(bytes: Uint8Array): string {
  const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
  return decoder.decodeToString(bytes);
}

function defaultConfig(): RuntimeConfig {
  return {
    appId: '',
    appName: '',
    serverUrl: DEFAULT_RUNTIME_CONFIG.serverUrl,
    node: { enable: false, entry: 'main.js', autostart: false },
    logging: { enabled: false },
  };
}

/**
 * Load `rawfile/capacitor.config.json`.
 *
 * The file is produced by `cap sync harmony` from the user's
 * `capacitor.config.ts`, so changing the web app config never requires
 * editing ArkTS.
 */
export function loadRuntimeConfig(context: common.UIAbilityContext): RuntimeConfig {
  try {
    const raw: Uint8Array = context.resourceManager.getRawFileContentSync(CONFIG_FILE);
    const parsed: RuntimeConfig = JSON.parse(decodeUtf8(raw)) as RuntimeConfig;
    // Defensive: only trust `files` when it really is an array — anything else
    // (missing key, wrong type after the JSON->interface hop) would silently
    // disable the primary unpack path.
    const parsedFiles = parsed.node?.files;
    const files: string[] = Array.isArray(parsedFiles) ? parsedFiles as string[] : [];
    return {
      appId: parsed.appId ?? '',
      appName: parsed.appName ?? '',
      serverUrl: parsed.serverUrl ?? DEFAULT_RUNTIME_CONFIG.serverUrl,
      node: {
        enable: parsed.node?.enable === true,
        entry: parsed.node?.entry ?? 'main.js',
        autostart: parsed.node?.autostart === true,
        files: files,
      },
      logging: {
        enabled: parsed.logging?.enabled === true,
      },
    };
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'no usable %{public}s — using defaults. %{public}s', CONFIG_FILE, String(e));
    return defaultConfig();
  }
}

/**
 * Copy `rawfile/node/**` into the app's writable `filesDir`.
 *
 * The embedded Node.js runtime needs a real filesystem path (`require()`,
 * `fs.readFileSync`, …) while rawfile content is only reachable through the
 * resource manager, so we unpack it on first launch.  The list of files is
 * taken from the runtime config (`node.files`, embedded by `cap sync
 * harmony`) and falls back to the `rawfile/node/file-list.json` manifest.
 *
 * Already-extracted files are skipped unless their size differs, so upgrades
 * are cheap.
 *
 * The destination dir is ALWAYS created, even when there is nothing to
 * extract: the native runtime writes `node-boot.log` there, and a missing
 * dir is otherwise indistinguishable from a native crash on-device (exit
 * code 1, no log, no output).  Per-file failures are collected into the
 * returned report instead of vanishing into hilog, so the app UI can show
 * exactly why the backend never came up.
 */
export function extractNodeBundle(context: common.UIAbilityContext, destDir: string, files?: string[]): ExtractReport {
  const report: ExtractReport = { copied: 0, skipped: 0, failed: 0, error: '' };
  ensureDir(destDir);

  let fileList: string[] = files ?? [];
  if (fileList.length === 0) {
    try {
      const raw: Uint8Array = context.resourceManager.getRawFileContentSync(NODE_FILE_LIST);
      fileList = JSON.parse(decodeUtf8(raw)) as string[];
    } catch (e) {
      report.error = `empty node.files in config and ${NODE_FILE_LIST} unreadable: ${String(e)}`;
      hilog.warn(DOMAIN, TAG, '%{public}s', report.error);
      return report;
    }
  }

  for (const relative of fileList) {
    if (relative.startsWith('.') || relative === NODE_FILE_LIST_NAME) {
      continue;
    }
    try {
      const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(`node/${relative}`);
      const target: string = `${destDir}/${relative}`;
      ensureDir(target.substring(0, target.lastIndexOf('/')));
      let skip: boolean = false;
      try {
        if (fs.statSync(target).size === bytes.byteLength) {
          skip = true;
        }
      } catch (e) {
        // file does not exist yet
      }
      if (skip) {
        report.skipped++;
        continue;
      }
      const file = fs.openSync(target, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
      fs.closeSync(file);
      report.copied++;
    } catch (e) {
      report.failed++;
      if (report.error.length === 0) {
        report.error = `extract ${relative} failed: ${String(e)}`;
      }
      hilog.warn(DOMAIN, TAG, 'failed to extract %{public}s: %{public}s', relative, String(e));
    }
  }
  hilog.info(DOMAIN, TAG, 'extracted %{public}d node file(s) to %{public}s (skipped %{public}d, failed %{public}d)',
    report.copied, destDir, report.skipped, report.failed);
  return report;
}

function ensureDir(dir: string): void {
  if (dir.length === 0) {
    return;
  }
  try {
    fs.accessSync(dir);
    return;
  } catch (e) {
    // does not exist yet
  }
  try {
    fs.mkdirSync(dir, true);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'mkdir %{public}s failed: %{public}s', dir, String(e));
  }
}
