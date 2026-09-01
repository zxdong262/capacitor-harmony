import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall, PluginData } from '../PluginCall';

const TAG: string = 'NetworkPlugin';
const DOMAIN: number = 0x0000;

/**
 * `@capacitor/network` — connectivity status.
 *
 * Emits `networkStatusChange` whenever the default network appears, changes
 * bearer, or disappears.
 */
export class NetworkPlugin extends CapacitorPlugin {
  private connected: boolean = false;
  private connectionType: string = 'none';
  private netConn: connection.NetConnection | null = null;

  getPluginId(): string {
    return 'Network';
  }

  getMethods(): string[] {
    return ['getStatus'];
  }

  load(): void {
    this.detect(null);
    this.watch();
  }

  getStatus(call: PluginCall): void {
    this.detect(call);
  }

  private watch(): void {
    try {
      const netConn: connection.NetConnection = connection.createNetConnection();
      netConn.on('netAvailable', () => {
        this.detect(null);
      });
      netConn.on('netCapabilitiesChange', () => {
        this.detect(null);
      });
      netConn.on('netLost', () => {
        this.apply(false, 'none');
      });
      netConn.on('netUnavailable', () => {
        this.apply(false, 'none');
      });
      this.netConn = netConn;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'cannot watch network changes: %{public}s', String(e));
    }
  }

  private detect(call: PluginCall | null): void {
    connection
      .hasDefaultNet()
      .then((has: boolean) => {
        if (!has) {
          this.apply(false, 'none');
          if (call) {
            call.resolve(this.status() as Object);
          }
          return;
        }
        connection
          .getDefaultNet()
          .then((handle: connection.NetHandle) => {
            connection
              .getNetCapabilities(handle)
              .then((caps: connection.NetCapabilities) => {
                this.apply(true, this.mapBearer(caps.bearerTypes));
                if (call) {
                  call.resolve(this.status() as Object);
                }
              })
              .catch(() => {
                this.apply(true, 'unknown');
                if (call) {
                  call.resolve(this.status() as Object);
                }
              });
          })
          .catch(() => {
            this.apply(false, 'none');
            if (call) {
              call.resolve(this.status() as Object);
            }
          });
      })
      .catch(() => {
        this.apply(false, 'none');
        if (call) {
          call.resolve(this.status() as Object);
        }
      });
  }

  private mapBearer(bearerTypes: Array<connection.NetBearType> | undefined): string {
    if (!bearerTypes || bearerTypes.length === 0) {
      return 'unknown';
    }
    if (bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) {
      return 'wifi';
    }
    if (bearerTypes.includes(connection.NetBearType.BEARER_ETHERNET)) {
      return 'ethernet';
    }
    if (bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR)) {
      return 'cellular';
    }
    if (bearerTypes.includes(connection.NetBearType.BEARER_BLUETOOTH)) {
      return 'bluetooth';
    }
    return 'unknown';
  }

  private status(): PluginData {
    const snapshot: PluginData = {
      connected: this.connected,
      connectionType: this.connectionType,
    };
    return snapshot;
  }

  private apply(connected: boolean, connectionType: string): void {
    const changed: boolean = this.connected !== connected || this.connectionType !== connectionType;
    this.connected = connected;
    this.connectionType = connectionType;
    if (changed) {
      this.notifyListeners('networkStatusChange', this.status() as Object);
    }
  }
}
