import { batteryInfo, deviceInfo } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { preferences } from '@kit.ArkData';
import { statfs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall, PluginData } from '../PluginCall';

const ID_STORE: string = 'capacitor_device';
const ID_KEY: string = 'uuid';

/**
 * `@capacitor/device` — device, OS, language and battery information.
 */
export class DevicePlugin extends CapacitorPlugin {
  getPluginId(): string {
    return 'Device';
  }

  getMethods(): string[] {
    return ['getInfo', 'getId', 'getBatteryInfo', 'getLanguageCode', 'getLanguageTag'];
  }

  getInfo(call: PluginCall): void {
    this.getFreeDisk((diskFree: number) => {
      const result: PluginData = {
        name: deviceInfo.marketName ?? deviceInfo.productModel ?? '',
        model: deviceInfo.productModel ?? '',
        platform: 'harmony',
        operatingSystem: 'harmonyos',
        osVersion: deviceInfo.displayVersion ?? deviceInfo.osFullName ?? '',
        manufacturer: deviceInfo.manufacture ?? deviceInfo.brand ?? '',
        isVirtual: false,
        memUsed: 0,
        diskFree: diskFree,
        diskTotal: 0,
        realDiskFree: diskFree,
        realDiskTotal: 0,
        webViewVersion: '',
        apiLevel: deviceInfo.sdkApiVersion ?? 0,
      };
      call.resolve(result);
    });
  }

  getId(call: PluginCall): void {
    preferences
      .getPreferences(this.context, ID_STORE)
      .then((store: preferences.Preferences) => {
        const existing: string = store.getSync(ID_KEY, '') as string;
        if (existing.length > 0) {
          const result: PluginData = { identifier: existing };
          call.resolve(result);
          return;
        }
        const generated: string = util.generateRandomUUID(true);
        store.putSync(ID_KEY, generated);
        store.flush();
        const fresh: PluginData = { identifier: generated };
        call.resolve(fresh);
      })
      .catch((e: Error) => {
        call.reject(`getId failed: ${e.message}`);
      });
  }

  getBatteryInfo(call: PluginCall): void {
    const level: number = (batteryInfo.batterySOC ?? 0) / 100;
    const result: PluginData = {
      batteryLevel: level,
      isCharging: this.isCharging(),
    };
    call.resolve(result);
  }

  getLanguageCode(call: PluginCall): void {
    const result: PluginData = { value: this.getLanguage() };
    call.resolve(result);
  }

  getLanguageTag(call: PluginCall): void {
    const result: PluginData = { value: this.getLocale() };
    call.resolve(result);
  }

  private getLanguage(): string {
    try {
      return i18n.System.getSystemLanguage();
    } catch (e) {
      return 'en';
    }
  }

  private getLocale(): string {
    try {
      return i18n.System.getSystemLocale();
    } catch (e) {
      return this.getLanguage();
    }
  }

  private isCharging(): boolean {
    const status: number = batteryInfo.chargingStatus ?? 0;
    // BatteryChargeState: NONE=0, ENABLE=1, DISABLE=2, FULL=3
    return status === 1 || status === 3;
  }

  private getFreeDisk(done: (bytes: number) => void): void {
    try {
      statfs
        .getFreeSize(this.context.filesDir)
        .then((size: number) => {
          done(size);
        })
        .catch(() => {
          done(0);
        });
    } catch (e) {
      done(0);
    }
  }
}
