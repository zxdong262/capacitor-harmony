import { promptAction } from '@kit.ArkUI';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';

/**
 * `@capacitor/toast` — short transient messages.
 */
export class ToastPlugin extends CapacitorPlugin {
  getPluginId(): string {
    return 'Toast';
  }

  getMethods(): string[] {
    return ['show'];
  }

  show(call: PluginCall): void {
    const text: string = call.getString('text');
    const duration: number = call.getInt('duration', 2000);
    const position: string = call.getString('position', 'bottom');
    const lines: number = call.getInt('textMaxLines', 1);

    const options: promptAction.ShowToastOptions = {
      message: text,
      duration: duration,
      bottom: position === 'bottom' ? 50 : undefined,
      showMode: promptAction.ToastShowMode.DEFAULT,
    };
    // `textMaxLines` is not part of the ArkUI toast API; it is accepted for
    // API compatibility and ignored here.
    void lines;

    try {
      promptAction.showToast(options);
      call.resolve();
    } catch (e) {
      call.reject(`show toast failed: ${String(e)}`);
    }
  }
}
