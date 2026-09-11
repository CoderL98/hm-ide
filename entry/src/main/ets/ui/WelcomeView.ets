import { IdeTheme } from '../theme/IdeColors';
import { IdeStore } from '../services/IdeStore';
import { SettingsStore } from '../services/SettingsStore';
import { WorkspaceService } from '../services/WorkspaceService';
import { RemoteConnectDialog } from './remote/RemoteConnectDialog';

@Component
export struct WelcomeView {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;
  @StorageLink('remoteSessionRev') remoteSessionRev: number = 0;

  private remoteDialog: CustomDialogController | null = null;

  private openRemoteDialog(): void {
    this.remoteDialog = new CustomDialogController({
      builder: RemoteConnectDialog({
        onConnected: () => {
          IdeStore.getInstance().bumpFromRemote();
        }
      }),
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.remoteDialog.open();
  }

  build() {
    Column({ space: 16 }) {
      Text('鸿蒙原生IDE')
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontColor(IdeTheme.palette().foreground)

      Text('Scheme B：本地为编辑器壳，默认打开远程 Linux 文件夹（hm-ide-agent）。本地沙箱示例为次要演示。')
        .fontSize(13)
        .fontColor(IdeTheme.palette().mutedForeground)
        .lineHeight(20)
        .width('100%')
        .constraintSize({ maxWidth: 460 })

      Row({ space: 10 }) {
        Text('打开远程文件夹')
          .fontSize(13)
          .fontColor(IdeTheme.palette().primaryForeground)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(6)
          .backgroundColor(IdeTheme.palette().primary)
          .onClick(() => this.openRemoteDialog())

        Text('打开本地示例')
          .fontSize(13)
          .fontColor(IdeTheme.palette().foreground)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(6)
          .backgroundColor(IdeTheme.palette().muted)
          .border({ width: 1, color: IdeTheme.palette().border })
          .onClick(() => IdeStore.getInstance().openSampleProject())

        Text('命令面板')
          .fontSize(13)
          .fontColor(IdeTheme.palette().foreground)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(6)
          .backgroundColor(IdeTheme.palette().muted)
          .border({ width: 1, color: IdeTheme.palette().border })
          .onClick(() => IdeStore.getInstance().openCommandPalette())
      }
      .margin({ top: 8 })

      Text('最近打开')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(IdeTheme.palette().mutedForeground)
        .width('100%')
        .constraintSize({ maxWidth: 460 })
        .margin({ top: 12 })

      Column({ space: 4 }) {
        if (SettingsStore.getInstance().recentRoots.length === 0) {
          Text('暂无记录')
            .fontSize(12.5)
            .fontColor(IdeTheme.palette().gutter)
        } else {
          ForEach(SettingsStore.getInstance().recentRoots, (root: string) => {
            Text(root === WorkspaceService.getInstance().getRootPath()
              ? `HelloWorld（本地沙箱示例）`
              : root)
              .fontSize(12.5)
              .fontColor(IdeTheme.palette().mutedForeground)
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .width('100%')
              .borderRadius(4)
              .backgroundColor(IdeTheme.palette().card)
              .border({ width: 1, color: IdeTheme.palette().border })
              .onClick(() => IdeStore.getInstance().openRecentRoot(root))
          }, (root: string) => root)
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 460 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(24)
    .backgroundColor(IdeTheme.palette().editor)
  }
}
