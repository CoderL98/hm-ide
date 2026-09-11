import { IdeTheme } from '../theme/IdeColors';
import { IdeStore } from '../services/IdeStore';
import { SettingsStore } from '../services/SettingsStore';
import { router } from '@kit.ArkUI';

@Component
export struct PhoneBottomNav {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;

  private items: string[] = ['files', 'editor', 'terminal', 'settings'];

  private label(id: string): string {
    switch (id) {
      case 'files':
        return '文件';
      case 'editor':
        return '编辑';
      case 'terminal':
        return '终端';
      case 'settings':
        return '设置';
      default:
        return id;
    }
  }

  private glyph(id: string): string {
    switch (id) {
      case 'files':
        return '📂';
      case 'editor':
        return '✎';
      case 'terminal':
        return '>_';
      case 'settings':
        return '⚙';
      default:
        return '·';
    }
  }

  build() {
    Row() {
      ForEach(this.items, (id: string) => {
        Column({ space: 3 }) {
          Text(this.glyph(id))
            .fontSize(16)
            .fontColor(IdeStore.getInstance().phoneNav === id
              ? IdeTheme.palette().foreground
              : IdeTheme.palette().mutedForeground)
          Text(this.label(id))
            .fontSize(10)
            .fontColor(IdeStore.getInstance().phoneNav === id
              ? IdeTheme.palette().foreground
              : IdeTheme.palette().mutedForeground)
        }
        .layoutWeight(1)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (id === 'settings') {
            router.pushUrl({ url: 'pages/SettingsPage' });
            return;
          }
          IdeStore.getInstance().setPhoneNav(id);
        })
      }, (id: string) => id)
    }
    .width('100%')
    .height(56)
    .backgroundColor(IdeTheme.palette().card)
    .border({ width: { top: 1 }, color: IdeTheme.palette().border })
  }
}

@Component
export struct PhoneSideRail {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;

  private items: string[] = ['files', 'editor', 'terminal', 'settings'];

  private label(id: string): string {
    switch (id) {
      case 'files':
        return '文件';
      case 'editor':
        return '编辑';
      case 'terminal':
        return '终端';
      case 'settings':
        return '设置';
      default:
        return id;
    }
  }

  private glyph(id: string): string {
    switch (id) {
      case 'files':
        return '📂';
      case 'editor':
        return '✎';
      case 'terminal':
        return '>_';
      case 'settings':
        return '⚙';
      default:
        return '·';
    }
  }

  build() {
    Column({ space: 2 }) {
      ForEach(this.items, (id: string) => {
        Column({ space: 2 }) {
          Text(this.glyph(id)).fontSize(14)
          Text(this.label(id))
            .fontSize(9)
            .fontColor(IdeStore.getInstance().phoneNav === id
              ? IdeTheme.palette().foreground
              : IdeTheme.palette().mutedForeground)
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .borderRadius(6)
        .backgroundColor(IdeStore.getInstance().phoneNav === id
          ? IdeTheme.palette().muted
          : Color.Transparent)
        .onClick(() => {
          if (id === 'settings') {
            router.pushUrl({ url: 'pages/SettingsPage' });
            return;
          }
          IdeStore.getInstance().setPhoneNav(id);
        })
      }, (id: string) => id)
    }
    .width(52)
    .height('100%')
    .padding({ top: 6, bottom: 6 })
    .backgroundColor(IdeTheme.palette().card)
    .border({ width: { right: 1 }, color: IdeTheme.palette().border })
  }
}

@Component
export struct IdeTitleBar {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;
  @Prop title: string = '鸿蒙原生IDE';
  @Prop showTraffic: boolean = true;

  build() {
    Row() {
      if (this.showTraffic) {
        Row({ space: 6 }) {
          Circle().width(10).height(10).fill(IdeTheme.palette().muted)
            .stroke(IdeTheme.palette().borderSubtle).strokeWidth(1)
          Circle().width(10).height(10).fill(IdeTheme.palette().muted)
            .stroke(IdeTheme.palette().borderSubtle).strokeWidth(1)
          Circle().width(10).height(10).fill(IdeTheme.palette().muted)
            .stroke(IdeTheme.palette().borderSubtle).strokeWidth(1)
        }
        .padding({ right: 8 })
      }

      Text(this.title)
        .fontSize(12)
        .fontColor(IdeTheme.palette().mutedForeground)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)

      Text('打开…')
        .fontSize(11.5)
        .fontColor(IdeTheme.palette().mutedForeground)
        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
        .onClick(() => IdeStore.getInstance().openCommandPalette())

      Text('查找')
        .fontSize(11.5)
        .fontColor(IdeTheme.palette().mutedForeground)
        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
        .onClick(() => IdeStore.getInstance().requestFind())

      Text('主题')
        .fontSize(11.5)
        .fontColor(IdeTheme.palette().mutedForeground)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .border({ width: 1, color: IdeTheme.palette().border })
        .borderRadius(4)
        .onClick(() => {
          const next = IdeTheme.isDark() ? 'light' : 'dark';
          SettingsStore.getInstance().setThemeMode(next);
        })
    }
    .width('100%')
    .height(36)
    .padding({ left: 12, right: 12 })
    .backgroundColor(IdeTheme.palette().card)
    .border({ width: { bottom: 1 }, color: IdeTheme.palette().border })
  }
}
