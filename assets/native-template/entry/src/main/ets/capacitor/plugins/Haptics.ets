import { vibrator } from '@kit.SensorServiceKit';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';

/**
 * `@capacitor/haptics` — tactile feedback.
 *
 * Uses the system vibrator; requires `ohos.permission.VIBRATE`.
 */
export class HapticsPlugin extends CapacitorPlugin {
  getPluginId(): string {
    return 'Haptics';
  }

  getMethods(): string[] {
    return ['impact', 'vibrate', 'selectionStart', 'selectionChanged', 'selectionEnd'];
  }

  impact(call: PluginCall): void {
    const style: string = call.getString('style', 'medium');
    const duration: number = style === 'heavy' ? 35 : style === 'light' ? 10 : 20;
    this.buzz(duration, call);
  }

  vibrate(call: PluginCall): void {
    this.buzz(call.getNumber('duration', 300), call);
  }

  selectionStart(call: PluginCall): void {
    this.buzz(5, call);
  }

  selectionChanged(call: PluginCall): void {
    this.buzz(5, call);
  }

  selectionEnd(call: PluginCall): void {
    this.buzz(5, call);
  }

  private buzz(durationMs: number, call: PluginCall): void {
    try {
      const effect: vibrator.VibrateEffect = { type: 'time', duration: durationMs };
      const attr: vibrator.VibrateAttribute = { usage: 'touch', id: 0 };
      vibrator.startVibration(effect, attr);
      call.resolve();
    } catch (e) {
      call.reject(`vibration failed: ${String(e)}`);
    }
  }
}
