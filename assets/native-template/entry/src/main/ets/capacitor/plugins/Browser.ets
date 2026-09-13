import { common, Want } from '@kit.AbilityKit';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';

/**
 * `@capacitor/browser` — open a URL in the system browser.
 */
export class BrowserPlugin extends CapacitorPlugin {
  getPluginId(): string {
    return 'Browser';
  }

  getMethods(): string[] {
    return ['open', 'close'];
  }

  open(call: PluginCall): void {
    const url: string = call.getString('url');
    if (url.length === 0 || !(url.startsWith('http://') || url.startsWith('https://'))) {
      call.reject('only absolute http(s) URLs are supported');
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url,
    };
    this.context
      .startAbility(want)
      .then(() => {
        call.resolve();
      })
      .catch((e: Error) => {
        call.reject(`cannot open ${url}: ${e.message}`, 'OPEN_FAILED');
      });
  }

  close(call: PluginCall): void {
    // No in-app tab is kept open on HarmonyOS, so there is nothing to close.
    call.resolve();
  }
}
