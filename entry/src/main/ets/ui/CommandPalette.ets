import { IdeTheme } from '../theme/IdeColors';
import { IdeStore } from '../services/IdeStore';
import { QuickOpenItem } from '../models/FileNode';

/**
 * 轻量命令面板：模糊打开工作区文件（Ctrl/Cmd+P 或按钮）
 */
@Component
export struct CommandPalette {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000088')
        .onClick(() => IdeStore.getInstance().closeCommandPalette())

      Column({ space: 0 }) {
        TextInput({
          text: IdeStore.getInstance().commandQuery,
          placeholder: '输入文件名以快速打开…'
        })
          .height(40)
          .fontSize(14)
          .backgroundColor(IdeTheme.palette().card)
          .fontColor(IdeTheme.palette().foreground)
          .placeholderColor(IdeTheme.palette().mutedForeground)
          .padding({ left: 14, right: 14 })
          .onChange((v: string) => IdeStore.getInstance().setCommandQuery(v))
          .onSubmit(() => {
            const items = IdeStore.getInstance().commandItems;
            if (items.length > 0) {
              IdeStore.getInstance().pickCommandItem(items[0]);
            }
          })

        List() {
          ForEach(IdeStore.getInstance().commandItems, (item: QuickOpenItem) => {
            ListItem() {
              Column({ space: 2 }) {
                Text(item.name)
                  .fontSize(13)
                  .fontColor(IdeTheme.palette().foreground)
                  .width('100%')
                Text(item.relPath)
                  .fontSize(11)
                  .fontColor(IdeTheme.palette().mutedForeground)
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .width('100%')
              .onClick(() => IdeStore.getInstance().pickCommandItem(item))
            }
          }, (item: QuickOpenItem) => item.path)
        }
        .constraintSize({ maxHeight: 320 })
        .scrollBar(BarState.Auto)
        .backgroundColor(IdeTheme.palette().card)
      }
      .width('90%')
      .constraintSize({ maxWidth: 520 })
      .margin({ top: 72 })
      .borderRadius(8)
      .border({ width: 1, color: IdeTheme.palette().border })
      .clip(true)
      .backgroundColor(IdeTheme.palette().card)
    }
    .width('100%')
    .height('100%')
    .visibility(IdeStore.getInstance().commandPaletteOpen ? Visibility.Visible : Visibility.None)
  }
}
