import { IdeTheme } from '../theme/IdeColors';
import { IdeStore } from '../services/IdeStore';
import { SettingsStore } from '../services/SettingsStore';
import { WindowSizeState, IdeShellMode } from '../layout/Breakpoint';
import { ActivityBar } from './ActivityBar';
import { SidePanelHost } from './SidePanelHost';
import { ExplorerPanel } from './ExplorerPanel';
import { EditorColumn } from './EditorColumn';
import { StatusBar } from './StatusBar';
import { IdeTitleBar, PhoneBottomNav, PhoneSideRail } from './PhoneChrome';
import { BottomPanel } from './BottomPanel';
import { VSplitter } from './Splitter';
import { CommandPalette } from './CommandPalette';

/**
 * 自适应 IDE 壳层 — 对齐 design/prototypes 各方向布局
 */
@Component
export struct AdaptiveShell {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;
  @StorageLink('workspaceRev') workspaceRev: number = 0;
  @State win: WindowSizeState = new WindowSizeState();

  aboutToAppear(): void {
    // 初始尺寸由外层 onAreaChange 更新
  }

  private titleText(): string {
    const tab = IdeStore.getInstance().getActiveTab();
    const name = tab ? tab.name : '';
    return name ? `鸿蒙原生IDE — HelloWorld · ${name}` : '鸿蒙原生IDE — HelloWorld';
  }

  private resolvedSidebarWidth(): number {
    const mode = this.win.shellMode();
    // 桌面 / 折叠：使用可拖拽持久化宽度；其它形态用断点默认
    if (mode === IdeShellMode.DESKTOP || mode === IdeShellMode.FOLD_LANDSCAPE) {
      return SettingsStore.getInstance().sidebarWidth;
    }
    return this.win.sidebarWidth();
  }

  private showSidebarNow(): boolean {
    const mode = this.win.shellMode();
    if (mode === IdeShellMode.PHONE_PORTRAIT) {
      return IdeStore.getInstance().phoneNav === 'files';
    }
    if (mode === IdeShellMode.PHONE_LANDSCAPE) {
      return IdeStore.getInstance().phoneNav === 'files' ||
        IdeStore.getInstance().phoneNav === 'editor';
    }
    if (!SettingsStore.getInstance().sidebarVisible) {
      return false;
    }
    return this.win.showSidebar();
  }

  @Builder
  DesktopLike(fold: boolean) {
    Column() {
      IdeTitleBar({ title: this.titleText(), showTraffic: !fold })
      if (fold) {
        Row() {
          Text('折叠屏横屏')
            .fontSize(11)
            .fontColor(IdeTheme.palette().mutedForeground)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .border({ width: 1, color: IdeTheme.palette().border })
            .borderRadius(4)
            .backgroundColor(IdeTheme.palette().muted)
          Text('HelloWorld')
            .fontSize(13.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(IdeTheme.palette().foreground)
            .margin({ left: 10 })
          Text('近平板密度')
            .fontSize(12)
            .fontColor(IdeTheme.palette().mutedForeground)
            .margin({ left: 8 })
          Blank()
        }
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .backgroundColor(IdeTheme.palette().card)
        .border({ width: { bottom: 1 }, color: IdeTheme.palette().border })
      }
      Row() {
        if (this.win.showActivityBar()) {
          ActivityBar({ compact: fold })
        }
        if (this.showSidebarNow()) {
          SidePanelHost({ panelWidth: this.resolvedSidebarWidth() })
          VSplitter({ baseWidth: this.resolvedSidebarWidth() })
        }
        EditorColumn({
          showTabs: true,
          showBreadcrumb: true,
          showBottom: this.win.showBottomPanel(),
          foldCompact: fold
        })
      }
      .layoutWeight(1)
      .width('100%')

      if (this.win.showStatusBar()) {
        StatusBar({ modeLabel: this.win.modeLabel(), compact: fold })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TabletShell(portrait: boolean) {
    Column() {
      Row() {
        Text('HelloWorld')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(IdeTheme.palette().foreground)
        Text(portrait ? '平板竖屏' : '平板横屏')
          .fontSize(12)
          .fontColor(IdeTheme.palette().mutedForeground)
          .margin({ left: 8 })
        Blank()
        Text('打开…')
          .fontSize(11.5)
          .fontColor(IdeTheme.palette().mutedForeground)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => IdeStore.getInstance().openCommandPalette())
        Text('主题')
          .fontSize(11.5)
          .fontColor(IdeTheme.palette().mutedForeground)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .border({ width: 1, color: IdeTheme.palette().border })
          .borderRadius(4)
          .onClick(() => {
            SettingsStore.getInstance().setThemeMode(IdeTheme.isDark() ? 'light' : 'dark');
          })
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 16 })
      .backgroundColor(IdeTheme.palette().card)
      .border({ width: { bottom: 1 }, color: IdeTheme.palette().border })

      Row() {
        if (this.showSidebarNow()) {
          SidePanelHost({ panelWidth: this.win.sidebarWidth() })
        }
        EditorColumn({
          showTabs: true,
          showBreadcrumb: !portrait,
          showBottom: true,
          foldCompact: false
        })
      }
      .layoutWeight(1)
      .width('100%')

      StatusBar({ modeLabel: this.win.modeLabel(), compact: false })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  PhonePortraitShell() {
    Column() {
      Row() {
        Text(IdeStore.getInstance().activeTabName('鸿蒙原生IDE'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(IdeTheme.palette().foreground)
          .layoutWeight(1)
        Text('打开…')
          .fontSize(11.5)
          .fontColor(IdeTheme.palette().mutedForeground)
          .padding({ left: 8, right: 8 })
          .onClick(() => IdeStore.getInstance().openCommandPalette())
        Text('主题')
          .fontSize(11.5)
          .fontColor(IdeTheme.palette().mutedForeground)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .border({ width: 1, color: IdeTheme.palette().border })
          .borderRadius(4)
          .onClick(() => {
            SettingsStore.getInstance().setThemeMode(IdeTheme.isDark() ? 'light' : 'dark');
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 12 })
      .border({ width: { bottom: 1 }, color: IdeTheme.palette().border })

      if (IdeStore.getInstance().phoneNav === 'files') {
        ExplorerPanel({ panelWidth: 0 })
          .width('100%')
          .layoutWeight(1)
      } else if (IdeStore.getInstance().phoneNav === 'terminal') {
        Column() {
          BottomPanel({ foldCompact: false, expand: true })
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        Column() {
          Row({ space: 6 }) {
            Text(IdeStore.getInstance().activeTabName('未打开'))
              .fontSize(12)
              .fontColor(IdeTheme.palette().mutedForeground)
            if (IdeStore.getInstance().activeTabDirty()) {
              Circle().width(7).height(7).fill(IdeTheme.palette().dirty)
            }
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .margin({ left: 12, top: 10 })
          .backgroundColor(IdeTheme.palette().card)
          .border({ width: 1, color: IdeTheme.palette().border })
          .borderRadius(6)
          .onClick(() => IdeStore.getInstance().setPhoneNav('files'))

          EditorColumn({
            showTabs: false,
            showBreadcrumb: false,
            showBottom: false
          })
            .layoutWeight(1)
        }
        .layoutWeight(1)
        .width('100%')
      }

      PhoneBottomNav()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  PhoneLandscapeShell() {
    Column() {
      Row() {
        PhoneSideRail()
        if (IdeStore.getInstance().phoneNav === 'files' ||
          (IdeStore.getInstance().phoneNav === 'editor' && SettingsStore.getInstance().sidebarVisible)) {
          if (IdeStore.getInstance().phoneNav !== 'terminal') {
            ExplorerPanel({ panelWidth: 180 })
          }
        }
        if (IdeStore.getInstance().phoneNav === 'terminal') {
          Column() {
            BottomPanel({ foldCompact: true, expand: true })
          }
          .layoutWeight(1)
        } else {
          Column() {
            Row() {
              Text(IdeStore.getInstance().activeTabName('编辑'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(IdeTheme.palette().foreground)
                .layoutWeight(1)
              Text('主题')
                .fontSize(11)
                .fontColor(IdeTheme.palette().mutedForeground)
                .onClick(() => {
                  SettingsStore.getInstance().setThemeMode(IdeTheme.isDark() ? 'light' : 'dark');
                })
            }
            .width('100%')
            .height(32)
            .padding({ left: 10, right: 10 })
            .backgroundColor(IdeTheme.palette().card)
            .border({ width: { bottom: 1 }, color: IdeTheme.palette().border })

            EditorColumn({
              showTabs: false,
              showBreadcrumb: false,
              showBottom: false
            })
              .layoutWeight(1)
          }
          .layoutWeight(1)
          .height('100%')
        }
      }
      .layoutWeight(1)
      .width('100%')

      StatusBar({ modeLabel: this.win.modeLabel(), compact: true })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Column() {
        if (this.win.shellMode() === IdeShellMode.DESKTOP) {
          this.DesktopLike(false)
        } else if (this.win.shellMode() === IdeShellMode.FOLD_LANDSCAPE) {
          this.DesktopLike(true)
        } else if (this.win.shellMode() === IdeShellMode.TABLET_LANDSCAPE) {
          this.TabletShell(false)
        } else if (this.win.shellMode() === IdeShellMode.TABLET_PORTRAIT) {
          this.TabletShell(true)
        } else if (this.win.shellMode() === IdeShellMode.PHONE_LANDSCAPE) {
          this.PhoneLandscapeShell()
        } else {
          this.PhonePortraitShell()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(IdeTheme.palette().background)
      .onAreaChange((_old: Area, area: Area) => {
        const w = Number(area.width);
        const h = Number(area.height);
        if (w > 0 && h > 0) {
          this.win.update(w, h);
        }
      })

      CommandPalette()
    }
    .width('100%')
    .height('100%')
  }
}
