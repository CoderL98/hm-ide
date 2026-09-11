import { IdeTheme, IdeThemeMode } from '../theme/IdeColors';
import { SettingsStore } from '../services/SettingsStore';
import { IdeStore } from '../services/IdeStore';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct SettingsPage {
  @StorageLink('settingsRev') settingsRev: number = 0;

  private modes: IdeThemeMode[] = ['dark', 'light', 'system'];
  private fontSizes: number[] = [12, 13, 14, 16, 18];
  private tabSizes: number[] = [2, 4];

  build() {
    Column() {
      Row() {
        Text('← 返回')
          .fontSize(14)
          .fontColor(IdeTheme.palette().mutedForeground)
          .onClick(() => router.back())
        Text('设置')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(IdeTheme.palette().foreground)
          .margin({ left: 16 })
        Blank()
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
      .border({ width: { bottom: 1 }, color: IdeTheme.palette().border })

      Scroll() {
        Column({ space: 16 }) {
          Text('外观')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(IdeTheme.palette().mutedForeground)
            .width('100%')

          Text('主题')
            .fontSize(13)
            .fontColor(IdeTheme.palette().foreground)
            .width('100%')

          Row({ space: 8 }) {
            ForEach(this.modes, (m: IdeThemeMode) => {
              Text(IdeTheme.modeLabel(m))
                .fontSize(12.5)
                .fontColor(SettingsStore.getInstance().themeMode === m
                  ? IdeTheme.palette().primaryForeground
                  : IdeTheme.palette().foreground)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .borderRadius(6)
                .backgroundColor(SettingsStore.getInstance().themeMode === m
                  ? IdeTheme.palette().primary
                  : IdeTheme.palette().muted)
                .onClick(() => {
                  SettingsStore.getInstance().setThemeMode(m);
                })
            }, (m: IdeThemeMode) => m)
          }
          .width('100%')

          Text('编辑器字号')
            .fontSize(13)
            .fontColor(IdeTheme.palette().foreground)
            .width('100%')
            .margin({ top: 8 })

          Row({ space: 8 }) {
            ForEach(this.fontSizes, (n: number) => {
              Text(`${n}`)
                .fontSize(12.5)
                .fontColor(SettingsStore.getInstance().fontSize === n
                  ? IdeTheme.palette().primaryForeground
                  : IdeTheme.palette().foreground)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .borderRadius(6)
                .backgroundColor(SettingsStore.getInstance().fontSize === n
                  ? IdeTheme.palette().primary
                  : IdeTheme.palette().muted)
                .onClick(() => {
                  SettingsStore.getInstance().setFontSize(n);
                })
            }, (n: number) => `${n}`)
          }
          .width('100%')

          Text('缩进（Tab 宽度）')
            .fontSize(13)
            .fontColor(IdeTheme.palette().foreground)
            .width('100%')
            .margin({ top: 8 })

          Row({ space: 8 }) {
            ForEach(this.tabSizes, (n: number) => {
              Text(`${n} 空格`)
                .fontSize(12.5)
                .fontColor(SettingsStore.getInstance().tabSize === n
                  ? IdeTheme.palette().primaryForeground
                  : IdeTheme.palette().foreground)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .borderRadius(6)
                .backgroundColor(SettingsStore.getInstance().tabSize === n
                  ? IdeTheme.palette().primary
                  : IdeTheme.palette().muted)
                .onClick(() => {
                  SettingsStore.getInstance().setTabSize(n);
                })
            }, (n: number) => `${n}`)
          }
          .width('100%')

          Text('布局')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(IdeTheme.palette().mutedForeground)
            .width('100%')
            .margin({ top: 16 })

          Text(`侧栏宽度 ${SettingsStore.getInstance().sidebarWidth} · 底栏高度 ${SettingsStore.getInstance().bottomPanelHeight}\n可在桌面壳层拖拽分割条调整，数值会持久化。`)
            .fontSize(12.5)
            .fontColor(IdeTheme.palette().mutedForeground)
            .width('100%')
            .lineHeight(20)

          Text('重置侧栏 / 底栏尺寸')
            .fontSize(12.5)
            .fontColor(IdeTheme.palette().foreground)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(6)
            .backgroundColor(IdeTheme.palette().muted)
            .onClick(() => {
              SettingsStore.getInstance().setSidebarWidth(260);
              SettingsStore.getInstance().setBottomPanelHeight(180);
            })

          Text('欢迎页')
            .fontSize(12.5)
            .fontColor(IdeTheme.palette().foreground)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(6)
            .backgroundColor(IdeTheme.palette().muted)
            .margin({ top: 8 })
            .onClick(() => {
              IdeStore.getInstance().goWelcome();
              router.back();
            })

          Text('关于')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(IdeTheme.palette().mutedForeground)
            .width('100%')
            .margin({ top: 16 })

          Text('鸿蒙原生IDE（hm-ide）v1.2.0
API 12+ Stage 模型脚手架。
编辑器：本地 Monaco + ArkTS tokenizer。
终端：xterm.js + 沙箱交互壳（非真实 OS PTY）。
不包含真实编译 / SSH 远端 / 调试器 / 完整 Git / 插件。')
            .fontSize(12.5)
            .fontColor(IdeTheme.palette().mutedForeground)
            .width('100%')
            .lineHeight(20)
        }
        .padding(16)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(IdeTheme.palette().background)
  }
}
