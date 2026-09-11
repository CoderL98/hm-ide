import { IdeTheme } from '../theme/IdeColors';
import { IdeStore } from '../services/IdeStore';
import { EditorTabBar, BreadcrumbBar } from './EditorTabBar';
import { MonacoWebEditor } from '../editor/MonacoWebEditor';
import { BottomPanel } from './BottomPanel';
import { HSplitter } from './Splitter';
import { WelcomeView } from './WelcomeView';

@Component
export struct EditorColumn {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;
  @Prop showTabs: boolean = true;
  @Prop showBreadcrumb: boolean = true;
  @Prop showBottom: boolean = true;
  @Prop foldCompact: boolean = false;

  build() {
    Column() {
      if (this.showTabs) {
        EditorTabBar()
      }
      if (this.showBreadcrumb && IdeStore.getInstance().getActiveTab()) {
        BreadcrumbBar()
      }
      Column() {
        if (IdeStore.getInstance().getActiveTab()) {
          MonacoWebEditor({
            contentRev: this.ideRev,
            settingsRev: this.settingsRev
          })
        } else {
          WelcomeView()
        }
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(IdeTheme.palette().editor)

      if (this.showBottom) {
        HSplitter()
        BottomPanel({ foldCompact: this.foldCompact })
      }
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .backgroundColor(IdeTheme.palette().editor)
  }
}
