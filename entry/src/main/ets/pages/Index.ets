import { AdaptiveShell } from '../ui/AdaptiveShell';
import { IdeTheme } from '../theme/IdeColors';
import { IdeStore } from '../services/IdeStore';

@Entry
@Component
struct Index {
  @StorageLink('settingsRev') settingsRev: number = 0;
  @StorageLink('ideRev') ideRev: number = 0;

  private isCtrl(event: KeyEvent): boolean {
    try {
      // API 12+：检测修饰键
      return event.getModifierKeyState(['Ctrl', 'Meta']) ||
        event.getModifierKeyState(['Control']) ||
        event.getModifierKeyState(['Meta']);
    } catch (_e) {
      return false;
    }
  }

  build() {
    Column() {
      AdaptiveShell()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(IdeTheme.palette().background)
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent) => {
      if (event.type !== KeyType.Down) {
        return;
      }
      const t = (event.keyText || '').toLowerCase();
      const ctrl = this.isCtrl(event);
      if (ctrl && t === 'p') {
        IdeStore.getInstance().openCommandPalette();
      } else if (ctrl && t === 'f') {
        IdeStore.getInstance().requestFind();
      } else if (ctrl && t === 'h') {
        IdeStore.getInstance().requestReplace();
      } else if (t === 'escape' || t === 'esc') {
        if (IdeStore.getInstance().commandPaletteOpen) {
          IdeStore.getInstance().closeCommandPalette();
        }
      }
    })
  }
}
