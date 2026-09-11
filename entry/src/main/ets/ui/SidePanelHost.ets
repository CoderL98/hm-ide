import { IdeStore } from '../services/IdeStore';
import { ExplorerPanel } from './ExplorerPanel';
import { SearchPanel } from './SearchPanel';
import { ScmPanel } from './ScmPanel';
import { ExtensionsPanel } from './ExtensionsPanel';

/**
 * 按活动栏选中项切换侧栏内容
 */
@Component
export struct SidePanelHost {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;
  @Prop panelWidth: number = 260;

  build() {
    if (IdeStore.getInstance().activity === 'search') {
      SearchPanel({ panelWidth: this.panelWidth })
    } else if (IdeStore.getInstance().activity === 'scm') {
      ScmPanel({ panelWidth: this.panelWidth })
    } else if (IdeStore.getInstance().activity === 'extensions') {
      ExtensionsPanel({ panelWidth: this.panelWidth })
    } else {
      ExplorerPanel({ panelWidth: this.panelWidth })
    }
  }
}
