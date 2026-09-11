import { IdeTheme } from '../theme/IdeColors';

/** 扩展活动项空状态 */
@Component
export struct ExtensionsPanel {
  @StorageLink('settingsRev') settingsRev: number = 0;
  @Prop panelWidth: number = 260;

  build() {
    Column() {
      Row() {
        Text('扩展')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(IdeTheme.palette().mutedForeground)
          .letterSpacing(0.5)
        Blank()
      }
      .width('100%')
      .height(35)
      .padding({ left: 12, right: 8 })

      Column({ space: 8 }) {
        Text('插件系统未启用')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(IdeTheme.palette().foreground)
        Text('范围外：插件市场与扩展宿主。')
          .fontSize(12)
          .fontColor(IdeTheme.palette().mutedForeground)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 24 })
      .width('100%')
      .layoutWeight(1)
    }
    .width(this.panelWidth > 0 ? this.panelWidth : '100%')
    .height('100%')
    .backgroundColor(IdeTheme.palette().sidebar)
    .border({ width: { right: 1 }, color: IdeTheme.palette().border })
  }
}
