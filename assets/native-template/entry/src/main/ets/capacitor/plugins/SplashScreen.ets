import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall, PluginData } from '../PluginCall';

/**
 * `@capacitor/splash-screen` — thin wrapper over the system launch window.
 *
 * The splash is the ability's `startWindowIcon`; it is not controllable at
 * runtime the way Android's is, so `hide()` simply resolves and
 * `splashScreenHidden` fires once a listener registers.
 *
 * Event: `splashScreenHidden`.
 */
export class SplashScreenPlugin extends CapacitorPlugin {
  getPluginId(): string {
    return 'SplashScreen';
  }

  getMethods(): string[] {
    return ['show', 'hide'];
  }

  addListener(call: PluginCall): void {
    super.addListener(call);
    if (call.getString('eventName') === 'splashScreenHidden') {
      const payload: PluginData = {};
      this.notifyListeners('splashScreenHidden', payload);
    }
  }

  show(call: PluginCall): void {
    // The launch window was already replaced by the WebView; nothing to do.
    call.resolve();
  }

  hide(call: PluginCall): void {
    call.resolve();
  }
}
