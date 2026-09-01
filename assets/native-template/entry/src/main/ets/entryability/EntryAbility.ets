import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { window } from '@kit.ArkUI';
import { BridgeHolder } from '../capacitor/bridgeInstance';

const TAG: string = 'EntryAbility';
const DOMAIN: number = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s onCreate', this.context.abilityName);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s onDestroy', this.context.abilityName);
    BridgeHolder.bridge?.onDestroy();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // One-time ArkWeb engine init.  Must run before any Web component loads.
    webview.WebviewController.initializeWebEngine();

    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', err.message);
      }
    });
  }

  onWindowStageDestroy(): void {
    // no-op
  }

  onForeground(): void {
    BridgeHolder.bridge?.onResume();
  }

  onBackground(): void {
    BridgeHolder.bridge?.onPause();
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    BridgeHolder.bridge?.handleNewWant(want);
  }
}
