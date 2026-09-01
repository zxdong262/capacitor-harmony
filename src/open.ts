import { spawn } from 'child_process';
import { existsSync } from 'fs';
import { join } from 'path';
import type { HookEnv } from './env';
import { log, warn } from './util';

const DEEP_LINK = 'deveco://';

/**
 * `npx cap open harmony`
 *
 * DevEco Studio has no documented CLI entry point on macOS, so we try the
 * usual suspects in order and fall back to printing the project path.
 */
export async function open(env: HookEnv): Promise<void> {
  const projectDir = join(env.rootDir, 'harmony');
  if (!existsSync(projectDir)) {
    throw new Error(`HarmonyOS platform not found at ${projectDir}. Run: npx cap add harmony`);
  }

  const candidates: Array<[string, string[]]> = [
    ['/Applications/DevEco Studio.app/Contents/MacOS/studio', [projectDir]],
    ['/Applications/DevEco Studio.app/Contents/MacOS/devecostudio', [projectDir]],
    ['open', ['-a', 'DevEco Studio', projectDir]],
  ];

  for (const [cmd, args] of candidates) {
    if (cmd === 'open' || existsSync(cmd)) {
      try {
        const child = spawn(cmd, args, { stdio: 'ignore', detached: true });
        child.unref();
        log(`opened ${projectDir} in DevEco Studio`);
        return;
      } catch (e) {
        warn(`failed to launch "${cmd}": ${String(e)}`);
      }
    }
  }

  // Last resort: the deep link still lands the user in the IDE.
  try {
    const child = spawn('open', [DEEP_LINK], { stdio: 'ignore', detached: true });
    child.unref();
  } catch {
    // ignore
  }
  log(`open ${projectDir} in DevEco Studio`);
}
