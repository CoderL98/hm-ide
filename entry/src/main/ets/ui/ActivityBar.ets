import { IdeTheme } from '../theme/IdeColors';
import { IdeStore } from '../services/IdeStore';
import { ActivityId } from '../models/FileNode';
import { router } from '@kit.ArkUI';

@Component
export struct ActivityBar {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;
  @Prop compact: boolean = false;

  private items: ActivityId[] = ['explorer', 'search', 'scm', 'extensions'];

  private labelOf(id: ActivityId): string {
    switch (id) {
      case 'explorer':
        return '资源管理器';
      case 'search':
        return '搜索';
      case 'scm':
        return '源代码管理';
      case 'extensions':
        return '扩展';
      default:
        return '';
    }
  }

  private glyph(id: ActivityId): string {
    switch (id) {
      case 'explorer':
        return '📂';
      case 'search':
        return '⌕';
      case 'scm':
        return '⑂';
      case 'extensions':
        return '▦';
      default:
        return '·';
    }
  }

  @Builder
  Item(id: ActivityId) {
    Stack({ alignContent: Alignment.Start }) {
      // 左侧活动指示条（对齐原型）
      if (IdeStore.getInstance().activity === id) {
        Column()
          .width(2)
          .height(this.compact ? 20 : 24)
          .borderRadius(1)
          .backgroundColor(IdeTheme.palette().foreground)
          .margin({ left: 0 })
      }
      Column() {
        Text(this.glyph(id))
          .fontSize(this.compact ? 14 : 16)
          .fontColor(IdeStore.getInstance().activity === id
            ? IdeTheme.palette().foreground
            : IdeTheme.palette().mutedForeground)
      }
      .width(this.compact ? 36 : 40)
      .height(this.compact ? 36 : 40)
      .justifyContent(FlexAlign.Center)
      .borderRadius(6)
      .backgroundColor(IdeStore.getInstance().activity === id
        ? IdeTheme.palette().accent
        : Color.Transparent)
    }
    .width(this.compact ? 36 : 40)
    .height(this.compact ? 36 : 40)
    .margin({ top: 2, bottom: 2 })
    .onClick(() => {
      IdeStore.getInstance().setActivity(id);
    })
    .accessibilityText(this.labelOf(id))
  }

  build() {
    Column() {
      ForEach(this.items, (id: ActivityId) => {
        this.Item(id);
      }, (id: ActivityId) => id)

      Blank()

      Column() {
        Text('⚙')
          .fontSize(this.compact ? 14 : 16)
          .fontColor(IdeTheme.palette().mutedForeground)
      }
      .width(this.compact ? 36 : 40)
      .height(this.compact ? 36 : 40)
      .justifyContent(FlexAlign.Center)
      .borderRadius(6)
      .onClick(() => {
        router.pushUrl({ url: 'pages/SettingsPage' });
      })
      .accessibilityText('设置')
    }
    .width(48)
    .height('100%')
    .padding({ top: 8, bottom: 8 })
    .backgroundColor(IdeTheme.palette().activity)
    .border({ width: { right: 1 }, color: IdeTheme.palette().border })
  }
}
