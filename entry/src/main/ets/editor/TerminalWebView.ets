import { webview } from '@kit.ArkWeb';
import { LocalTerminalService } from '../services/LocalTerminalService';
import { IdeTheme } from '../theme/IdeColors';

/** JavaScriptProxy：Web → ArkTS */
class TerminalJsBridge {
  onReady(payload: string): void {
    try {
      AppStorage.setOrCreate('termReady', '1');
      const cur = AppStorage.get<number>('termReadyRev') ?? 0;
      AppStorage.setOrCreate('termReadyRev', cur + 1);
      try {
        const o = JSON.parse(payload) as Record<string, Object>;
        LocalTerminalService.getInstance().resize(Number(o['cols'] ?? 80), Number(o['rows'] ?? 24));
      } catch (_e) {
        // ignore
      }
      LocalTerminalService.getInstance().reattachFrontend();
    } catch (_e2) {
      // ignore
    }
  }

  onData(data: string): void {
    LocalTerminalService.getInstance().onInput(data);
  }

  onResize(payload: string): void {
    try {
      const o = JSON.parse(payload) as Record<string, Object>;
      LocalTerminalService.getInstance().resize(Number(o['cols'] ?? 80), Number(o['rows'] ?? 24));
    } catch (_e) {
      // ignore
    }
  }
}

/**
 * 底栏 xterm 宿主 ↔ LocalTerminalService（本地沙箱壳）
 */
@Component
export struct TerminalWebView {
  @StorageLink('termReadyRev') @Watch('onTermReady') termReadyRev: number = 0;
  @StorageLink('termDataRev') @Watch('onTermData') termDataRev: number = 0;
  @StorageLink('termCmdRev') @Watch('onTermCmd') termCmdRev: number = 0;
  @StorageLink('termSessionRev') termSessionRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;

  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: TerminalJsBridge = new TerminalJsBridge();
  private webReady: boolean = false;

  aboutToAppear(): void {
    LocalTerminalService.getInstance().ensureSession();
  }

  onTermReady(): void {
    this.webReady = true;
    this.runJs('window.__hmTerm && window.__hmTerm.setMode("local")');
    LocalTerminalService.getInstance().reattachFrontend();
  }

  onTermData(): void {
    const data = AppStorage.get<string>('termPendingData') ?? '';
    if (!data) {
      return;
    }
    this.runJs(`window.__hmTerm && window.__hmTerm.write(${JSON.stringify(data)})`);
  }

  onTermCmd(): void {
    const cmd = AppStorage.get<string>('termPendingCmd') ?? '';
    if (!cmd) {
      return;
    }
    if (cmd === 'clear') {
      this.runJs('window.__hmTerm && window.__hmTerm.clear()');
      return;
    }
    if (cmd.indexOf('mode:') === 0) {
      const mode = cmd.substring(5);
      this.runJs(`window.__hmTerm && window.__hmTerm.setMode(${JSON.stringify(mode)})`);
    }
  }

  private runJs(code: string): void {
    if (!this.webReady) {
      return;
    }
    try {
      this.controller.runJavaScript(code);
    } catch (_e) {
      // Web 未就绪
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text(LocalTerminalService.getInstance().capabilityLabel())
          .fontSize(11)
          .fontColor(IdeTheme.palette().mutedForeground)
        Blank()
        Text(`${LocalTerminalService.getInstance().cols}×${LocalTerminalService.getInstance().rows}`)
          .fontSize(11)
          .fontColor(IdeTheme.palette().gutter)
        Text(LocalTerminalService.getInstance().sessionActive ? '重启' : '启动')
          .fontSize(11)
          .fontColor(IdeTheme.palette().foreground)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(IdeTheme.palette().muted)
          .onClick(() => {
            const svc = LocalTerminalService.getInstance();
            if (svc.sessionActive) {
              svc.stopSession();
              svc.startSession();
            } else {
              svc.startSession();
            }
          })
      }
      .width('100%')
      .height(22)
      .padding({ left: 10, right: 10 })
      .backgroundColor(IdeTheme.palette().muted)

      Web({
        src: $rawfile('terminal-host/index.html'),
        controller: this.controller
      })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .onlineImageAccess(true)
        .javaScriptProxy({
          object: this.bridge,
          name: 'TerminalBridge',
          methodList: ['onReady', 'onData', 'onResize'],
          controller: this.controller
        })
        .onPageEnd((_url: string) => {
          this.runJs('window.__hmTerm && window.__hmTerm.fit()');
        })
    }
    .width('100%')
    .height('100%')
  }
}
