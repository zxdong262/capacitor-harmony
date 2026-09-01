import { hilog } from '@kit.PerformanceAnalysisKit';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';

const TAG: string = 'WebConsole';
const DOMAIN: number = 0x0000;

/**
 * `@capacitor/core` Console plugin — drains the WebView console to `hilog`
 * when `logging` is enabled in `capacitor.config.ts`.
 */
export class ConsolePlugin extends CapacitorPlugin {
  getPluginId(): string {
    return 'Console';
  }

  getMethods(): string[] {
    return ['log', 'debug', 'info', 'warn', 'error'];
  }

  log(call: PluginCall): void {
    this.forward('info', call.getString('message'));
    call.resolve();
  }

  debug(call: PluginCall): void {
    this.forward('debug', call.getString('message'));
    call.resolve();
  }

  info(call: PluginCall): void {
    this.forward('info', call.getString('message'));
    call.resolve();
  }

  warn(call: PluginCall): void {
    this.forward('warn', call.getString('message'));
    call.resolve();
  }

  error(call: PluginCall): void {
    this.forward('error', call.getString('message'));
    call.resolve();
  }

  private forward(level: string, message: string): void {
    switch (level) {
      case 'debug':
        hilog.debug(DOMAIN, TAG, '%{public}s', message);
        break;
      case 'warn':
        hilog.warn(DOMAIN, TAG, '%{public}s', message);
        break;
      case 'error':
        hilog.error(DOMAIN, TAG, '%{public}s', message);
        break;
      default:
        hilog.info(DOMAIN, TAG, '%{public}s', message);
    }
  }
}
