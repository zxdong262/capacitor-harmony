import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';

const TAG: string = 'KeyboardPlugin';
const DOMAIN: number = 0x0000;

/**
 * `@capacitor/keyboard` — soft keyboard visibility events.
 *
 * Method calls other than the listeners are accepted for API compatibility and
 * resolve, since HarmonyOS manages the keyboard automatically.
 *
 * Events: `keyboardWillShow`, `keyboardDidShow`, `keyboardWillHide`,
 * `keyboardDidHide`.
 */
export class KeyboardPlugin extends CapacitorPlugin {
  getPluginId(): string {
    return 'Keyboard';
  }

  getMethods(): string[] {
    return ['show', 'hide', 'setAccessoryBarVisible', 'setScroll', 'setStyle', 'setResizeMode'];
  }

  load(): void {
    window
      .getLastWindow(this.context)
      .then((win: window.Window) => {
        win.on('keyboardHeightChange', (height: number) => {
          const payload: Record<string, Object> = { keyboardHeight: height } as Record<string, Object>;
          if (height > 0) {
            this.notifyListeners('keyboardWillShow', payload as Object);
            this.notifyListeners('keyboardDidShow', payload as Object);
          } else {
            this.notifyListeners('keyboardWillHide', payload as Object);
            this.notifyListeners('keyboardDidHide', payload as Object);
          }
        });
      })
      .catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'cannot observe keyboard: %{public}s', e.message);
      });
  }

  show(call: PluginCall): void {
    call.unimplemented('show is not supported on HarmonyOS');
  }

  hide(call: PluginCall): void {
    call.unimplemented('hide is not supported on HarmonyOS');
  }

  setAccessoryBarVisible(call: PluginCall): void {
    call.resolve();
  }

  setScroll(call: PluginCall): void {
    call.resolve();
  }

  setStyle(call: PluginCall): void {
    call.resolve();
  }

  setResizeMode(call: PluginCall): void {
    call.resolve();
  }
}
