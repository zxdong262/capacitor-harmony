import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { BridgeHolder } from '../capacitor/bridgeInstance';
import { CapacitorBridge } from '../capacitor/CapacitorBridge';

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: CapacitorBridge | null = null;
  @State serverUrl: string = 'http://localhost/';

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = BridgeHolder.context!;
    this.bridge = new CapacitorBridge(ctx, this.controller);
    BridgeHolder.bridge = this.bridge;
    this.bridge.init();
    this.serverUrl = this.bridge.getServerUrl();
  }

  onBackPress(): boolean {
    if (this.bridge && this.bridge.onBackPressed()) {
      // A JS `backButton` listener consumed the gesture.
      return true;
    }
    return false;
  }

  build() {
    Column() {
      Web({ src: this.serverUrl, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .imageAccess(true)
        .mixedMode(MixedMode.All)
        .databaseAccess(true)
        .geolocationAccess(true)
        .cacheMode(CacheMode.Default)
        .javaScriptProxy({
          object: this.bridge!.getProxyObject(),
          name: 'harmonyBridge',
          methodList: ['postMessage'],
          controller: this.controller,
        })
        .onInterceptRequest((event: OnInterceptRequestEvent) => {
          if (!this.bridge) {
            return null;
          }
          return this.bridge.handleInterceptRequest(event.request);
        })
        .onPageEnd(() => {
          this.bridge?.onPageReady();
        })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
