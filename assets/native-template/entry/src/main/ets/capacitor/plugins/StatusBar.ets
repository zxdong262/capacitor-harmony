import { window } from '@kit.ArkUI';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';
import { StatusBarInfoPayload } from '../BridgeInterfaces';

/**
 * `@capacitor/status-bar` — the system status bar.
 */
export class StatusBarPlugin extends CapacitorPlugin {
  getPluginId(): string {
    return 'StatusBar';
  }

  getMethods(): string[] {
    return ['setStyle', 'setBackgroundColor', 'show', 'hide', 'getInfo', 'setOverlaysWebView'];
  }

  setStyle(call: PluginCall): void {
    const style: string = call.getString('style', 'DARK');
    const lightIcons: boolean = style === 'LIGHT';
    this.withWindow(call, (win: window.Window) => {
      win.setWindowSystemBarProperties({
        statusBarContentColor: lightIcons ? '#FFFFFF' : '#000000',
        isStatusBarLightIcon: lightIcons,
      });
      call.resolve();
    });
  }

  setBackgroundColor(call: PluginCall): void {
    const color: string = call.getString('color', '#000000');
    this.withWindow(call, (win: window.Window) => {
      win.setWindowSystemBarProperties({ statusBarColor: color });
      call.resolve();
    });
  }

  show(call: PluginCall): void {
    this.withWindow(call, (win: window.Window) => {
      win.setWindowSystemBarEnable(['status', 'navigation'] as Array<'status' | 'navigation'>);
      call.resolve();
    });
  }

  hide(call: PluginCall): void {
    this.withWindow(call, (win: window.Window) => {
      win.setWindowSystemBarEnable(['navigation'] as Array<'status' | 'navigation'>);
      call.resolve();
    });
  }

  getInfo(call: PluginCall): void {
    this.withWindow(call, (win: window.Window) => {
      const props: window.SystemBarProperties = win.getWindowSystemBarProperties();
      const lightIcons: boolean = props.isStatusBarLightIcon === true;
      const info: StatusBarInfoPayload = {
        visible: true,
        style: lightIcons ? 'LIGHT' : 'DARK',
        color: props.statusBarColor ?? '#000000',
        backgroundColor: props.statusBarColor ?? '#000000',
        contentOffset: 0,
        overlays: false,
      };
      call.resolve(info);
    });
  }

  setOverlaysWebView(call: PluginCall): void {
    const overlay: boolean = call.getBoolean('overlay', false);
    this.withWindow(call, (win: window.Window) => {
      win.setWindowLayoutFullScreen(overlay);
      win.setWindowSystemBarEnable(['status', 'navigation'] as Array<'status' | 'navigation'>);
      call.resolve();
    });
  }

  private withWindow(call: PluginCall, action: (win: window.Window) => void): void {
    window
      .getLastWindow(this.context)
      .then((win: window.Window) => {
        try {
          action(win);
        } catch (e) {
          call.reject(`status bar op failed: ${String(e)}`);
        }
      })
      .catch((e: Error) => {
        call.reject(`cannot get window: ${e.message}`);
      });
  }
}
