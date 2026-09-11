import { IdeTheme } from '../theme/IdeColors';
import { IdeStore } from '../services/IdeStore';
import { EditorTab } from '../models/FileNode';
import { WorkspaceService } from '../services/WorkspaceService';

@Component
export struct EditorTabBar {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;

  build() {
    Row() {
      Scroll() {
        Row() {
          ForEach(IdeStore.getInstance().tabs, (tab: EditorTab) => {
            Row() {
              Text(tab.name)
                .fontSize(12.5)
                .fontColor(IdeStore.getInstance().activeTabId === tab.id
                  ? IdeTheme.palette().foreground
                  : IdeTheme.palette().mutedForeground)
                .maxLines(1)
              if (tab.dirty) {
                Circle()
                  .width(7)
                  .height(7)
                  .fill(IdeTheme.palette().dirty)
                  .margin({ left: 8 })
              }
              Text('×')
                .fontSize(14)
                .fontColor(IdeTheme.palette().mutedForeground)
                .margin({ left: 8 })
                .onClick(() => {
                  IdeStore.getInstance().closeTab(tab.id);
                })
            }
            .padding({ left: 14, right: 14 })
            .height(35)
            .backgroundColor(IdeStore.getInstance().activeTabId === tab.id
              ? IdeTheme.palette().tabActive
              : IdeTheme.palette().tabInactive)
            .border({
              width: { right: 1 },
              color: IdeTheme.palette().border
            })
            .onClick(() => {
              IdeStore.getInstance().activateTab(tab.id);
            })
          }, (tab: EditorTab) => `${tab.id}-${tab.dirty}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)

      Text('查找')
        .fontSize(11.5)
        .fontColor(IdeTheme.palette().mutedForeground)
        .padding({ left: 8, right: 6 })
        .onClick(() => IdeStore.getInstance().requestFind())

      Text('替换')
        .fontSize(11.5)
        .fontColor(IdeTheme.palette().mutedForeground)
        .padding({ left: 6, right: 6 })
        .onClick(() => IdeStore.getInstance().requestReplace())

      Text('打开…')
        .fontSize(11.5)
        .fontColor(IdeTheme.palette().mutedForeground)
        .padding({ left: 6, right: 6 })
        .onClick(() => IdeStore.getInstance().openCommandPalette())

      Text('保存')
        .fontSize(11.5)
        .fontColor(IdeTheme.palette().mutedForeground)
        .padding({ left: 6, right: 10 })
        .onClick(() => {
          IdeStore.getInstance().saveActive();
        })
    }
    .width('100%')
    .height(35)
    .backgroundColor(IdeTheme.palette().tabInactive)
    .border({ width: { bottom: 1 }, color: IdeTheme.palette().border })
  }
}

@Component
export struct BreadcrumbBar {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;

  private crumbText(): string {
    const tab = IdeStore.getInstance().getActiveTab();
    if (!tab) {
      return '未打开文件';
    }
    return WorkspaceService.getInstance().relativePath(tab.path).split('/').join(' / ');
  }

  build() {
    Row() {
      Text(this.crumbText())
        .fontSize(12)
        .fontColor(IdeTheme.palette().mutedForeground)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(`ArkTS`)
        .fontSize(11)
        .fontColor(IdeTheme.palette().gutter)
    }
    .width('100%')
    .height(28)
    .padding({ left: 16, right: 16 })
    .backgroundColor(IdeTheme.palette().editor)
    .border({ width: { bottom: 1 }, color: IdeTheme.palette().border })
  }
}
