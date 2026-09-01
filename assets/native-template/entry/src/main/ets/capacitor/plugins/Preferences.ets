import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';

const TAG: string = 'PreferencesPlugin';
const DOMAIN: number = 0x0000;
const DEFAULT_GROUP: string = 'CapacitorStorage';

/**
 * `@capacitor/preferences` — the key/value store.
 *
 * Backed by HarmonyOS `preferences` (per-app XML store).  Values are persisted
 * as JSON so arbitrary objects, arrays and numbers survive a round trip.
 */
export class PreferencesPlugin extends CapacitorPlugin {
  private group: string = DEFAULT_GROUP;
  private store: preferences.Preferences | null = null;

  getPluginId(): string {
    return 'Preferences';
  }

  getMethods(): string[] {
    return ['configure', 'get', 'set', 'remove', 'keys', 'clear', 'migrate', 'removeOld'];
  }

  load(): void {
    preferences
      .getPreferences(this.context, this.group)
      .then((store: preferences.Preferences) => {
        this.store = store;
      })
      .catch((e: Error) => {
        hilog.error(DOMAIN, TAG, 'cannot open %{public}s: %{public}s', this.group, e.message);
      });
  }

  configure(call: PluginCall): void {
    const group: string = call.getString('group');
    if (group.length > 0 && group !== this.group) {
      this.group = group;
      this.store = null;
      this.load();
    }
    call.resolve();
  }

  get(call: PluginCall): void {
    const key: string = call.getString('key');
    this.withStore(call, (store: preferences.Preferences) => {
      const raw: Object = store.getSync(key, '') as Object;
      if (typeof raw !== 'string' || raw.length === 0) {
        call.resolve({ value: null } as Object);
        return;
      }
      try {
        call.resolve({ value: JSON.parse(raw) as Object } as Object);
      } catch (e) {
        // Stored before we switched to JSON, or written by native code.
        call.resolve({ value: raw } as Object);
      }
    });
  }

  set(call: PluginCall): void {
    const key: string = call.getString('key');
    const value: Object = call.options['value'] ?? (null as Object);
    this.withStore(call, (store: preferences.Preferences) => {
      try {
        store.putSync(key, JSON.stringify(value));
        store.flush();
        call.resolve();
      } catch (e) {
        call.reject(`set failed: ${String(e)}`);
      }
    });
  }

  remove(call: PluginCall): void {
    const key: string = call.getString('key');
    this.withStore(call, (store: preferences.Preferences) => {
      store.deleteSync(key);
      store.flush();
      call.resolve();
    });
  }

  keys(call: PluginCall): void {
    this.withStore(call, (store: preferences.Preferences) => {
      const all: Array<string> = store.getAllSync ? [] : [];
      call.resolve({ keys: this.collectKeys(store, all) } as Object);
    });
  }

  clear(call: PluginCall): void {
    this.withStore(call, (store: preferences.Preferences) => {
      store.clearSync();
      store.flush();
      call.resolve();
    });
  }

  migrate(call: PluginCall): void {
    // Nothing to migrate — this platform never used the old Cordova store.
    call.resolve({ migrated: [], existing: [] } as Object);
  }

  removeOld(call: PluginCall): void {
    call.resolve();
  }

  private collectKeys(store: preferences.Preferences, fallback: Array<string>): Array<string> {
    try {
      return store.getAllSync() ? Object.keys(store.getAllSync() as Object) : fallback;
    } catch (e) {
      return fallback;
    }
  }

  private withStore(call: PluginCall, action: (store: preferences.Preferences) => void): void {
    if (this.store) {
      action(this.store);
      return;
    }
    preferences
      .getPreferences(this.context, this.group)
      .then((store: preferences.Preferences) => {
        this.store = store;
        action(store);
      })
      .catch((e: Error) => {
        call.reject(`preferences unavailable: ${e.message}`);
      });
  }
}
