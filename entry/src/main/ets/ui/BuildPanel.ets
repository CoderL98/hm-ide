import { IdeTheme } from '../theme/IdeColors';
import { HvigorService } from '../services/HvigorService';

@Component
export struct BuildPanel {
  @StorageLink('buildRev') buildRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;
  @State sdkDraft: string = '';
  @State signDraft: string = '';

  aboutToAppear(): void {
    this.sdkDraft = HvigorService.getInstance().sdkPath;
    this.signDraft = HvigorService.getInstance().signingConfigPath;
  }

  build() {
    Column({ space: 10 }) {
      Text('HarmonyOS 构建')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(IdeTheme.palette().foreground)
        .width('100%')

      Text('SDK 路径（DevEco HarmonyOS SDK 根目录）')
        .fontSize(11)
        .fontColor(IdeTheme.palette().mutedForeground)
        .width('100%')
      TextInput({ text: this.sdkDraft, placeholder: '/path/to/Huawei/Sdk' })
        .height(32)
        .fontSize(12)
        .onChange((v: string) => {
          this.sdkDraft = v;
        })
      Row({ space: 8 }) {
        Text('保存 SDK')
          .fontSize(11)
          .fontColor(IdeTheme.palette().foreground)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(4)
          .backgroundColor(IdeTheme.palette().muted)
          .onClick(() => {
            HvigorService.getInstance().setSdkPath(this.sdkDraft);
          })
        Text('检测 SDK')
          .fontSize(11)
          .fontColor(IdeTheme.palette().foreground)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(4)
          .backgroundColor(IdeTheme.palette().muted)
          .onClick(() => {
            HvigorService.getInstance().detectSdk();
            this.sdkDraft = HvigorService.getInstance().sdkPath;
          })
      }

      Text('签名配置路径')
        .fontSize(11)
        .fontColor(IdeTheme.palette().mutedForeground)
        .width('100%')
      TextInput({ text: this.signDraft, placeholder: 'material / p7b 等路径（记录用）' })
        .height(32)
        .fontSize(12)
        .onChange((v: string) => {
          this.signDraft = v;
        })
      Text('保存签名配置')
        .fontSize(11)
        .fontColor(IdeTheme.palette().foreground)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(4)
        .backgroundColor(IdeTheme.palette().muted)
        .onClick(() => {
          HvigorService.getInstance().setSigningConfigPath(this.signDraft);
        })

      Text(HvigorService.getInstance().signingHint())
        .fontSize(11)
        .fontColor(IdeTheme.palette().gutter)
        .width('100%')

      Row({ space: 8 }) {
        Text('构建 entry')
          .fontSize(12)
          .fontColor(IdeTheme.palette().primaryForeground)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(6)
          .backgroundColor(IdeTheme.palette().primary)
          .onClick(() => {
            HvigorService.getInstance().assembleEntry();
          })
        Text('停止远端任务')
          .fontSize(12)
          .fontColor(IdeTheme.palette().foreground)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(6)
          .backgroundColor(IdeTheme.palette().muted)
          .onClick(() => {
            HvigorService.getInstance().killRemoteTask();
          })
      }

      Text(HvigorService.getInstance().lastResult || '尚未执行构建')
        .fontSize(12)
        .fontColor(IdeTheme.palette().mutedForeground)
        .width('100%')

      Scroll() {
        Text(HvigorService.getInstance().lastLog || '')
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(IdeTheme.palette().mutedForeground)
          .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .width('100%')
    .height('100%')
  }
}
