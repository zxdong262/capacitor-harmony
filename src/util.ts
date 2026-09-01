import { readFile, writeFile, pathExists, stat } from 'fs-extra';
import { dirname, join, relative } from 'path';

const log = (...args: unknown[]): void => console.log('[capacitor-harmony]', ...args);

export { log };

export function warn(...args: unknown[]): void {
  console.warn('[capacitor-harmony]', ...args);
}

export function fail(message: string): never {
  throw new Error(`[capacitor-harmony] ${message}`);
}

/**
 * Replace the value of a top-level string field in a `.json5` file without a
 * full JSON5 parser — `.json5` files in the HarmonyOS templates are simple
 * enough for this and it keeps the package dependency-free.
 *
 * Only rewrites `"key": "..."`; numbers, booleans and nested keys are left
 * alone so we never corrupt `module.json5`.
 */
export async function replaceJson5StringField(
  file: string,
  field: string,
  value: string,
): Promise<boolean> {
  if (!(await pathExists(file))) {
    return false;
  }
  const original = await readFile(file, 'utf8');
  const re = new RegExp(`("${field}"\\s*:\\s*)"([^"]*)"`);
  if (!re.test(original)) {
    return false;
  }
  const next = original.replace(re, (_m, prefix: string) => `${prefix}"${value}"`);
  if (next === original) {
    return false;
  }
  await writeFile(file, next);
  return true;
}

/**
 * Replace a JSON *array* literal assigned to `field` with `values`.
 * Used for `deviceTypes` in `module.json5`.
 */
export async function replaceJson5ArrayField(
  file: string,
  field: string,
  values: string[],
): Promise<boolean> {
  if (!(await pathExists(file))) {
    return false;
  }
  const original = await readFile(file, 'utf8');
  const re = new RegExp(`("${field}"\\s*:\\s*)\\[([^\\]]*)\\]`);
  if (!re.test(original)) {
    return false;
  }
  const body = values.map((v) => `"${v}"`).join(', ');
  const next = original.replace(re, (_m, prefix: string) => `${prefix}[${body}]`);
  if (next === original) {
    return false;
  }
  await writeFile(file, next);
  return true;
}

/** Read/update a HarmonyOS `element/string.json` resource file. */
export async function setStringResource(
  file: string,
  name: string,
  value: string,
): Promise<boolean> {
  if (!(await pathExists(file))) {
    return false;
  }
  const json = JSON.parse(await readFile(file, 'utf8')) as {
    string: Array<{ name: string; value: string }>;
  };
  if (!Array.isArray(json.string)) {
    return false;
  }
  const entry = json.string.find((s) => s.name === name);
  if (entry) {
    if (entry.value === value) {
      return false;
    }
    entry.value = value;
  } else {
    json.string.push({ name, value });
  }
  await writeFile(file, `${JSON.stringify(json, null, 2)}\n`);
  return true;
}

/** Recursively collect every file under `dir` as paths relative to `dir`. */
export async function listFiles(dir: string, base = dir): Promise<string[]> {
  const { readdir } = await import('fs-extra');
  if (!(await pathExists(dir))) {
    return [];
  }
  const entries = await readdir(dir, { withFileTypes: true });
  const out: string[] = [];
  for (const entry of entries) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...(await listFiles(full, base)));
    } else {
      out.push(relative(base, full));
    }
  }
  return out;
}

export async function isDirectory(path: string): Promise<boolean> {
  if (!(await pathExists(path))) {
    return false;
  }
  try {
    return (await stat(path)).isDirectory();
  } catch {
    return false;
  }
}

/** mkdir -p for a file path we are about to write. */
export async function ensureParentDir(file: string): Promise<void> {
  const { ensureDir } = await import('fs-extra');
  await ensureDir(dirname(file));
}

/** Escape a string so it can be embedded in a double-quoted ArkTS literal. */
export function etsString(value: string): string {
  return JSON.stringify(value ?? '');
}
