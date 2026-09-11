import { webview } from '@kit.ArkWeb';
import { IdeStore } from '../services/IdeStore';
import { SettingsStore } from '../services/SettingsStore';
import { IdeTheme } from '../theme/IdeColors';

/**
 * JavaScriptProxy 对象：Web → ArkTS
 */
class IdeJsBridge {
  onReady(payload: string): void {
    try {
      AppStorage.setOrCreate('editorEngine', payload);
      const cur = AppStorage.get<number>('editorReadyRev') ?? 0;
      AppStorage.setOrCreate('editorReadyRev', cur + 1);
    } catch (_e) {
      // ignore
    }
  }

  onChange(value: string): void {
    IdeStore.getInstance().onEditorChange(value);
  }

  onSaveRequest(_value: string): void {
    IdeStore.getInstance().saveActive();
  }
}

@Component
export struct MonacoWebEditor {
  @Prop @Watch('onExternalRev') contentRev: number = 0;
  @Prop @Watch('onSettingsRev') settingsRev: number = 0;
  @StorageLink('editorReadyRev') @Watch('onEditorReady') editorReadyRev: number = 0;
  @StorageLink('editorCmdRev') @Watch('onEditorCmd') editorCmdRev: number = 0;

  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: IdeJsBridge = new IdeJsBridge();
  private lastPath: string = '';
  private webReady: boolean = false;

  aboutToAppear(): void {
    // register early
  }

  onEditorReady(): void {
    this.webReady = true;
    this.pushActiveToWeb();
    this.pushSettingsToWeb();
  }

  onExternalRev(): void {
    this.pushActiveToWeb();
  }

  onSettingsRev(): void {
    this.pushSettingsToWeb();
  }

  onEditorCmd(): void {
    this.applyPendingCmd();
  }

  private escapeJs(s: string): string {
    return JSON.stringify(s);
  }

  private runJs(code: string): void {
    if (!this.webReady) {
      return;
    }
    try {
      this.controller.runJavaScript(code);
    } catch (_e) {
      // Web 尚未完成加载
    }
  }

  private applyPendingCmd(): void {
    const cmd = IdeStore.getInstance().consumeEditorCmd();
    if (!cmd) {
      return;
    }
    if (cmd === 'find') {
      this.runJs('window.__hmIde && window.__hmIde.triggerFind()');
      return;
    }
    if (cmd === 'replace') {
      this.runJs('window.__hmIde && window.__hmIde.triggerReplace()');
      return;
    }
    if (cmd.indexOf('reveal:') === 0) {
      const parts = cmd.split(':');
      const line = Number(parts[1] || '1');
      const col = Number(parts[2] || '1');
      this.runJs(`window.__hmIde && window.__hmIde.revealLine(${line},${col})`);
    }
  }

  private pushActiveToWeb(): void {
    const tab = IdeStore.getInstance().getActiveTab();
    if (!tab) {
      this.runJs('window.__hmIde && window.__hmIde.setValue("")');
      this.lastPath = '';
      return;
    }
    const pathChanged = tab.path !== this.lastPath;
    this.lastPath = tab.path;
    if (pathChanged) {
      this.runJs(
        `window.__hmIde && (window.__hmIde.setLanguage(${this.escapeJs(tab.language)}),` +
          `window.__hmIde.setValue(${this.escapeJs(tab.content)}))`
      );
      // 切换文件后可能有待 reveal
      this.applyPendingCmd();
    } else if (!tab.dirty) {
      this.runJs(`window.__hmIde && window.__hmIde.setValue(${this.escapeJs(tab.content)})`);
    }
  }

  private pushSettingsToWeb(): void {
    const s = SettingsStore.getInstance();
    const theme = IdeTheme.monacoThemeName();
    this.runJs(
      `window.__hmIde && (window.__hmIde.setTheme(${this.escapeJs(theme)}),` +
        `window.__hmIde.setFontSize(${s.fontSize}),window.__hmIde.setTabSize(${s.tabSize}))`
    );
  }

  build() {
    Web({
      src: $rawfile('monaco-host/index.html'),
      controller: this.controller
    })
      .width('100%')
      .height('100%')
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(true)
      .onlineImageAccess(true)
      .javaScriptProxy({
        object: this.bridge,
        name: 'IdeBridge',
        methodList: ['onReady', 'onChange', 'onSaveRequest'],
        controller: this.controller
      })
      .onPageEnd((_url: string) => {
        this.pushSettingsToWeb();
      })
  }
}
