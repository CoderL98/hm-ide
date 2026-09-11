import { IdeTheme } from '../theme/IdeColors';
import { IdeStore } from '../services/IdeStore';
import { SearchHit } from '../models/FileNode';

@Component
export struct SearchPanel {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;
  @Prop panelWidth: number = 260;

  build() {
    Column() {
      Row() {
        Text('搜索')
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
        TextInput({
          text: IdeStore.getInstance().searchQuery,
          placeholder: '在文件中搜索'
        })
          .height(32)
          .fontSize(12.5)
          .backgroundColor(IdeTheme.palette().muted)
          .fontColor(IdeTheme.palette().foreground)
          .placeholderColor(IdeTheme.palette().mutedForeground)
          .borderRadius(4)
          .padding({ left: 8, right: 8 })
          .onChange((v: string) => IdeStore.getInstance().setSearchQuery(v))
          .onSubmit(() => IdeStore.getInstance().runSearch())

        Row({ space: 8 }) {
          Text('搜索')
            .fontSize(12)
            .fontColor(IdeTheme.palette().primaryForeground)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(4)
            .backgroundColor(IdeTheme.palette().primary)
            .onClick(() => IdeStore.getInstance().runSearch())
          if (IdeStore.getInstance().searchBusy) {
            Text('…')
              .fontSize(12)
              .fontColor(IdeTheme.palette().mutedForeground)
          } else if (IdeStore.getInstance().searchQuery.trim().length > 0) {
            Text(`${IdeStore.getInstance().searchHits.length} 条结果`)
              .fontSize(11)
              .fontColor(IdeTheme.palette().mutedForeground)
          }
        }
        .width('100%')
      }
      .padding({ left: 12, right: 12, bottom: 8 })
      .width('100%')

      List() {
        ForEach(IdeStore.getInstance().searchHits, (hit: SearchHit) => {
          ListItem() {
            Column({ space: 2 }) {
              Text(`${hit.relPath}:${hit.line}`)
                .fontSize(11)
                .fontColor(IdeTheme.palette().foreground)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(hit.preview)
                .fontSize(11.5)
                .fontColor(IdeTheme.palette().mutedForeground)
                .fontFamily('monospace')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 12, right: 10, top: 8, bottom: 8 })
            .width('100%')
            .onClick(() => IdeStore.getInstance().openSearchHit(hit))
          }
        }, (hit: SearchHit, idx: number) => `${hit.path}:${hit.line}:${idx}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)

      if (IdeStore.getInstance().searchHits.length === 0 &&
        IdeStore.getInstance().searchQuery.trim().length > 0 &&
        !IdeStore.getInstance().searchBusy) {
        Text('无匹配结果')
          .fontSize(12)
          .fontColor(IdeTheme.palette().gutter)
          .padding(16)
      }
    }
    .width(this.panelWidth > 0 ? this.panelWidth : '100%')
    .height('100%')
    .backgroundColor(IdeTheme.palette().sidebar)
    .border({ width: { right: 1 }, color: IdeTheme.palette().border })
  }
}
