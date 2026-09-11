import { IdeTheme } from '../theme/IdeColors';
import { IdeStore } from '../services/IdeStore';
import { FileNode } from '../models/FileNode';
import { promptAction } from '@kit.ArkUI';
import { NameInputDialog } from './NameInputDialog';

@Component
export struct ExplorerPanel {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;
  /** 固定宽度；<=0 表示占满父容器宽度 */
  @Prop panelWidth: number = 260;

  private nameDialog: CustomDialogController | null = null;

  private openNameDialog(title: string, initial: string, onOk: (n: string) => void): void {
    this.nameDialog = new CustomDialogController({
      builder: NameInputDialog({
        title: title,
        placeholder: initial,
        initial: initial,
        onConfirm: onOk
      }),
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.nameDialog.open();
  }

  private confirmDelete(): void {
    const path = IdeStore.getInstance().selectedPath;
    if (!path) {
      return;
    }
    const name = path.substring(path.lastIndexOf('/') + 1);
    promptAction.showDialog({
      title: '删除',
      message: `确定删除 ${name}？`,
      buttons: [
        { text: '取消', color: IdeTheme.palette().mutedForeground },
        { text: '删除', color: '#f87171' }
      ]
    }).then((res) => {
      if (res.index === 1) {
        IdeStore.getInstance().deleteSelected();
      }
    });
  }

  @Builder
  TreeRow(node: FileNode) {
    Row({ space: 6 }) {
      if (node.isDirectory) {
        Text(node.expanded ? '▾' : '▸')
          .fontSize(10)
          .fontColor(IdeTheme.palette().mutedForeground)
          .width(12)
      } else {
        Text('')
          .width(12)
      }
      Text(node.isDirectory ? '📁' : '📄')
        .fontSize(11)
      Text(node.name)
        .fontSize(12.5)
        .fontColor(IdeStore.getInstance().selectedPath === node.path
          ? IdeTheme.palette().foreground
          : IdeTheme.palette().mutedForeground)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(26)
    .padding({
      left: 12 + node.depth * 12,
      right: 8
    })
    .backgroundColor(IdeStore.getInstance().selectedPath === node.path
      ? IdeTheme.palette().muted
      : Color.Transparent)
    .onClick(() => {
      IdeStore.getInstance().selectedPath = node.path;
      if (node.isDirectory) {
        IdeStore.getInstance().toggleFolder(node);
      } else {
        IdeStore.getInstance().openFile(node.path);
      }
    })
  }

  build() {
    Column() {
      Row() {
        Text('资源管理器')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(IdeTheme.palette().mutedForeground)
          .letterSpacing(0.4)
        Blank()
        Text('+')
          .fontSize(16)
          .fontColor(IdeTheme.palette().mutedForeground)
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .borderRadius(4)
          .onClick(() => {
            this.openNameDialog('新建文件', 'NewFile.ets', (n: string) => {
              IdeStore.getInstance().createFileInSelection(n);
            });
          })
        Text('⊞')
          .fontSize(12)
          .fontColor(IdeTheme.palette().mutedForeground)
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.openNameDialog('新建文件夹', 'new-folder', (n: string) => {
              IdeStore.getInstance().createFolderInSelection(n);
            });
          })
        Text('↻')
          .fontSize(13)
          .fontColor(IdeTheme.palette().mutedForeground)
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .onClick(() => IdeStore.getInstance().refreshTree())
        Text('✎')
          .fontSize(12)
          .fontColor(IdeTheme.palette().mutedForeground)
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            const path = IdeStore.getInstance().selectedPath;
            if (!path) {
              return;
            }
            const old = path.substring(path.lastIndexOf('/') + 1);
            this.openNameDialog('重命名', old, (n: string) => {
              IdeStore.getInstance().renameSelected(n);
            });
          })
        Text('⌫')
          .fontSize(12)
          .fontColor(IdeTheme.palette().mutedForeground)
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .onClick(() => this.confirmDelete())
      }
      .width('100%')
      .height(35)
      .padding({ left: 12, right: 8 })

      List() {
        ForEach(IdeStore.getInstance().flatTree(), (node: FileNode) => {
          ListItem() {
            this.TreeRow(node);
          }
        }, (node: FileNode) => `${node.path}-${node.expanded}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)
      .padding({ top: 4, bottom: 12 })
    }
    .width(this.panelWidth > 0 ? this.panelWidth : '100%')
    .height('100%')
    .backgroundColor(IdeTheme.palette().sidebar)
    .border({ width: { right: 1 }, color: IdeTheme.palette().border })
  }
}
