import { pasteboard } from '@kit.BasicServicesKit';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall, PluginData } from '../PluginCall';

/**
 * `@capacitor/clipboard` — system pasteboard.
 */
export class ClipboardPlugin extends CapacitorPlugin {
  getPluginId(): string {
    return 'Clipboard';
  }

  getMethods(): string[] {
    return ['read', 'write'];
  }

  write(call: PluginCall): void {
    const value: string = call.getString('string');
    if (value.length === 0) {
      call.reject('a non-empty "string" is required');
      return;
    }
    try {
      const board = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
      board
        .setData(data)
        .then(() => {
          call.resolve();
        })
        .catch((e: Error) => {
          call.reject(`clipboard write failed: ${e.message}`);
        });
    } catch (e) {
      call.reject(`clipboard write failed: ${String(e)}`);
    }
  }

  read(call: PluginCall): void {
    try {
      const board = pasteboard.getSystemPasteboard();
      board
        .getData()
        .then((data: pasteboard.PasteData) => {
          const read: PluginData = { value: data.getPrimaryText(), type: 'text/plain' };
          call.resolve(read);
        })
        .catch((e: Error) => {
          call.reject(`clipboard read failed: ${e.message}`);
        });
    } catch (e) {
      call.reject(`clipboard read failed: ${String(e)}`);
    }
  }
}
