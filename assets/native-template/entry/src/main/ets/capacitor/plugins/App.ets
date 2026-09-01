import { bundleManager } from '@kit.AbilityKit';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';

/**
 * `@capacitor/app` — lifecycle, launch URL and app metadata.
 *
 * Events: `appStateChange`, `pause`, `resume`, `appUrlOpen`, `backButton`.
 */
export class AppPlugin extends CapacitorPlugin {
  getPluginId(): string {
    return 'App';
  }

  getMethods(): string[] {
    return ['exitApp', 'getInfo', 'getLaunchUrl', 'getState', 'minimizeApp'];
  }

  getInfo(call: PluginCall): void {
    bundleManager
      .getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      .then((info: bundleManager.BundleInfo) => {
        call.resolve({
          id: info.name,
          name: info.name,
          build: String(info.versionCode ?? 0),
          version: info.versionName ?? '0.0.0',
        } as Object);
      })
      .catch((e: Error) => {
        call.reject(`getInfo failed: ${e.message}`);
      });
  }

  getState(call: PluginCall): void {
    call.resolve({ isActive: this.bridge.isAppActive() } as Object);
  }

  getLaunchUrl(call: PluginCall): void {
    const url: string = this.bridge.getLaunchUrl();
    call.resolve({ url: url } as Object);
  }

  exitApp(call: PluginCall): void {
    call.resolve();
    try {
      this.context.terminateSelf();
    } catch (e) {
      // Nothing sensible to do — the process is on its way out anyway.
    }
  }

  minimizeApp(call: PluginCall): void {
    // HarmonyOS has no "minimize to home" API for third-party apps.
    call.unimplemented('minimizeApp is not supported on HarmonyOS');
  }
}
