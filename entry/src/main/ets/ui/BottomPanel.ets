import { IdeTheme } from '../theme/IdeColors';
import { IdeStore } from '../services/IdeStore';
import { SettingsStore } from '../services/SettingsStore';
import { BottomPanelTab, ProblemItem } from '../models/FileNode';
import { TerminalWebView } from '../editor/TerminalWebView';
import { LocalTerminalService } from '../services/LocalTerminalService';
import { BuildPanel } from './BuildPanel';

@Component
export struct BottomPanel {
  @StorageLink('ideRev') ideRev: number = 0;
  @StorageLink('settingsRev') settingsRev: number = 0;
  @StorageLink('termSessionRev') termSessionRev: number = 0;
  @Prop foldCompact: boolean = false;
  /** 手机全屏终端等场景占满父容器 */
  @Prop expand: boolean = false;

  private tabs: BottomPanelTab[] = ['problems', 'output', 'terminal', 'build'];

  private label(t: BottomPanelTab): string {
    if (t === 'terminal') return '终端';
    if (t === 'output') return '输出';
    if (t === 'build') return '构建';
    return '问题';
  }

  private severityColor(sev: string): string {
    if (sev === 'error') return '#f87171';
    if (sev === 'warning') return '#fbbf24';
    return IdeTheme.palette().mutedForeground;
  }

  aboutToAppear(): void {
    if (IdeStore.getInstance().bottomTab === 'terminal') {
      LocalTerminalService.getInstance().ensureSession();
    }
  }

  build() {
    Column() {
      Row() {
        ForEach(this.tabs, (t: BottomPanelTab) => {
          Row({ space: 4 }) {
            Text(this.label(t))
              .fontSize(12)
              .fontColor(IdeStore.getInstance().bottomTab === t
                ? IdeTheme.palette().foreground
                : IdeTheme.palette().mutedForeground)
            if (t === 'problems' && IdeStore.getInstance().problems.length > 0) {
              Text(`${IdeStore.getInstance().problems.length}`)
                .fontSize(10)
                .fontColor(IdeTheme.palette().mutedForeground)
            }
          }
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(4)
          .backgroundColor(IdeStore.getInstance().bottomTab === t
            ? IdeTheme.palette().muted
            : Color.Transparent)
          .onClick(() => {
            IdeStore.getInstance().setBottomTab(t);
            if (t === 'terminal') {
              LocalTerminalService.getInstance().ensureSession();
            }
          })
        }, (t: BottomPanelTab) => t)

        Blank()

        Text(SettingsStore.getInstance().bottomPanelCollapsed ? '▴' : '▾')
          .fontSize(12)
          .fontColor(IdeTheme.palette().mutedForeground)
          .padding(6)
          .onClick(() => {
            SettingsStore.getInstance().setBottomPanelCollapsed(
              !SettingsStore.getInstance().bottomPanelCollapsed);
          })
      }
      .width('100%')
      .height(32)
      .padding({ left: 8, right: 8 })
      .border({ width: { bottom: 1 }, color: IdeTheme.palette().border })

      if (!SettingsStore.getInstance().bottomPanelCollapsed) {
        if (IdeStore.getInstance().bottomTab === 'problems') {
          Scroll() {
            Column({ space: 2 }) {
              if (IdeStore.getInstance().problems.length === 0) {
                Text('目前没有问题。')
                  .fontSize(12.5)
                  .fontColor(IdeTheme.palette().gutter)
              } else {
                ForEach(IdeStore.getInstance().problems, (p: ProblemItem, idx: number) => {
                  Row({ space: 8 }) {
                    Text(p.severity === 'error' ? 'E' : (p.severity === 'warning' ? 'W' : 'I'))
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.severityColor(p.severity))
                      .width(14)
                    Text(`${p.file}:${p.line}  ${p.message}`)
                      .fontSize(12.5)
                      .fontColor(IdeTheme.palette().mutedForeground)
                      .fontFamily('monospace')
                      .layoutWeight(1)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('100%')
                  .padding({ top: 4, bottom: 4 })
                  .onClick(() => IdeStore.getInstance().openProblem(p))
                }, (p: ProblemItem, idx: number) =>
                  `${p.path}-${p.line}-${p.message}-${idx}`)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        } else if (IdeStore.getInstance().bottomTab === 'terminal') {
          TerminalWebView()
            .layoutWeight(1)
            .width('100%')
        } else if (IdeStore.getInstance().bottomTab === 'build') {
          BuildPanel()
            .layoutWeight(1)
            .width('100%')
        } else {
          Scroll() {
            Column({ space: 2 }) {
              ForEach(
                IdeStore.getInstance().outputLines,
                (line: string, idx: number) => {
                  Text(line)
                    .fontSize(12.5)
                    .fontColor(IdeTheme.palette().mutedForeground)
                    .fontFamily('monospace')
                    .width('100%')
                }, (line: string, idx: number) => `${idx}-${line}`)
            }
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        }
      }
    }
    .width('100%')
    .height(this.expand
      ? '100%'
      : (SettingsStore.getInstance().bottomPanelCollapsed
        ? 32
        : (this.foldCompact
          ? Math.min(120, SettingsStore.getInstance().bottomPanelHeight)
          : SettingsStore.getInstance().bottomPanelHeight)))
    .backgroundColor(IdeTheme.palette().card)
    .border({ width: { top: this.expand ? 0 : 1 }, color: IdeTheme.palette().border })
  }
}
