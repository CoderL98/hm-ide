import { IdeTheme } from '../theme/IdeColors';
import { SettingsStore } from '../services/SettingsStore';
import { IdeStore } from '../services/IdeStore';
import { LocalTerminalService } from '../services/LocalTerminalService';
import { RemoteSession } from '../services/remote/RemoteSession';

@Component
export struct StatusBar {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;
  @StorageLink('termSessionRev') termSessionRev: number = 0;
  @StorageLink('remoteSessionRev') remoteSessionRev: number = 0;
  @Prop modeLabel: string = '';
  @Prop compact: boolean = false;

  private workspaceLabel(): string {
    const rs = RemoteSession.getInstance();
    if (rs.isRemote()) {
      return rs.statusBarLabel() || '远程';
    }
    return '沙箱工作区';
  }

  build() {
    Row() {
      Row({ space: 5 }) {
        Circle()
          .width(6)
          .height(6)
          .fill(RemoteSession.getInstance().isRemote()
            ? IdeTheme.palette().primary
            : IdeTheme.palette().statusOk)
        Text(this.workspaceLabel())
          .fontSize(this.compact ? 11 : 11.5)
          .fontColor(IdeTheme.palette().mutedForeground)
      }

      Text(this.modeLabel)
        .fontSize(this.compact ? 11 : 11.5)
        .fontColor(IdeTheme.palette().mutedForeground)
        .margin({ left: 12 })

      Text(LocalTerminalService.getInstance().statusBarLabel())
        .fontSize(this.compact ? 11 : 11.5)
        .fontColor(IdeTheme.palette().mutedForeground)
        .margin({ left: 12 })
        .onClick(() => IdeStore.getInstance().setBottomTab('terminal'))

      if (IdeStore.getInstance().problems.length > 0) {
        Text(`问题 ${IdeStore.getInstance().problems.length}`)
          .fontSize(this.compact ? 11 : 11.5)
          .fontColor(IdeTheme.palette().mutedForeground)
          .margin({ left: 12 })
          .onClick(() => IdeStore.getInstance().setBottomTab('problems'))
      }

      Blank()

      Text(`UTF-8  ·  LF  ·  ArkTS  ·  Tab ${SettingsStore.getInstance().tabSize}`)
        .fontSize(this.compact ? 11 : 11.5)
        .fontColor(IdeTheme.palette().mutedForeground)

      Text(IdeTheme.isDark() ? '深色' : '浅色')
        .fontSize(this.compact ? 11 : 11.5)
        .fontColor(IdeTheme.palette().mutedForeground)
        .margin({ left: 12 })
        .onClick(() => {
          const next = IdeTheme.isDark() ? 'light' : 'dark';
          SettingsStore.getInstance().setThemeMode(next);
        })
    }
    .width('100%')
    .height(this.compact ? 22 : 24)
    .padding({ left: 10, right: 10 })
    .backgroundColor(IdeTheme.palette().status)
    .border({ width: { top: 1 }, color: IdeTheme.palette().border })
  }
}
