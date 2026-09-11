import { IdeTheme } from '../theme/IdeColors';
import { GitService, GitStatusItem } from '../services/GitService';
import { IdeStore } from '../services/IdeStore';

/**
 * 源代码管理 — libhm_git / libgit2；未链接时显示诚实空状态 + 初始化入口
 */
@Component
export struct ScmPanel {
  @StorageLink('settingsRev') settingsRev: number = 0;
  @StorageLink('scmRev') scmRev: number = 0;
  @Prop panelWidth: number = 260;
  @State commitMsg: string = '';

  aboutToAppear(): void {
    GitService.getInstance().refresh();
  }

  private statusColor(st: string): string {
    if (st === 'added' || st === 'untracked') {
      return '#4ade80';
    }
    if (st === 'deleted' || st === 'conflicted') {
      return '#f87171';
    }
    return '#fbbf24';
  }

  build() {
    Column() {
      Row() {
        Text('源代码管理')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(IdeTheme.palette().mutedForeground)
          .letterSpacing(0.5)
        Blank()
        Text('刷新')
          .fontSize(11)
          .fontColor(IdeTheme.palette().foreground)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(IdeTheme.palette().muted)
          .onClick(() => {
            GitService.getInstance().refresh();
          })
      }
      .width('100%')
      .height(35)
      .padding({ left: 12, right: 8 })

      Text(GitService.getInstance().capabilityLabel())
        .fontSize(11)
        .fontColor(IdeTheme.palette().gutter)
        .padding({ left: 12, right: 12 })
        .width('100%')
        .margin({ bottom: 6 })

      if (!GitService.getInstance().libgit2Linked && !GitService.getInstance().remoteSource) {
        Column({ space: 10 }) {
          Text('libgit2 未链接')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(IdeTheme.palette().foreground)
          Text('本地 libgit2 未链接。连接远程 Agent 后将使用 git.status / git.diff。或设置 CMake -DHM_GIT2_ROOT=… 启用设备端。')
            .fontSize(12)
            .fontColor(IdeTheme.palette().mutedForeground)
            .lineHeight(18)
            .width('100%')
          Text(GitService.getInstance().lastError || '详见 native/third_party/README.md')
            .fontSize(11)
            .fontColor(IdeTheme.palette().gutter)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 16 })
        .width('100%')
        .layoutWeight(1)
      } else if (!GitService.getInstance().repoOpen) {
        Column({ space: 10 }) {
          Text('工作区不是 Git 仓库')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(IdeTheme.palette().foreground)
          Text('可初始化空仓库（libgit2 git_repository_init）。')
            .fontSize(12)
            .fontColor(IdeTheme.palette().mutedForeground)
            .width('100%')
          Text('git init')
            .fontSize(12)
            .fontColor(IdeTheme.palette().primaryForeground)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(6)
            .backgroundColor(IdeTheme.palette().primary)
            .onClick(() => {
              const r = GitService.getInstance().initRepo();
              IdeStore.getInstance().appendOutput(`[Git] init: ${r.err} ${r.message}`);
            })
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 16 })
        .width('100%')
        .layoutWeight(1)
      } else {
        Column({ space: 8 }) {
          Text(`分支 ${GitService.getInstance().branch}`)
            .fontSize(12)
            .fontColor(IdeTheme.palette().foreground)
            .width('100%')

          TextInput({ text: this.commitMsg, placeholder: '提交说明…' })
            .height(32)
            .fontSize(12)
            .onChange((v: string) => {
              this.commitMsg = v;
            })

          Row({ space: 8 }) {
            Text('全部暂存')
              .fontSize(11)
              .fontColor(IdeTheme.palette().foreground)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(4)
              .backgroundColor(IdeTheme.palette().muted)
              .onClick(() => {
                const r = GitService.getInstance().add('.');
                IdeStore.getInstance().appendOutput(`[Git] add: ${r.err} ${r.message}`);
                GitService.getInstance().refresh();
              })
            Text('提交')
              .fontSize(11)
              .fontColor(IdeTheme.palette().primaryForeground)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(4)
              .backgroundColor(IdeTheme.palette().primary)
              .onClick(() => {
                const msg = this.commitMsg.trim() || 'hm-ide commit';
                const r = GitService.getInstance().commit(msg);
                IdeStore.getInstance().appendOutput(`[Git] commit: ${r.err} ${r.message}`);
                this.commitMsg = '';
              })
          }

          Scroll() {
            Column({ space: 4 }) {
              if (GitService.getInstance().statusItems.length === 0) {
                Text('工作区清洁')
                  .fontSize(12)
                  .fontColor(IdeTheme.palette().gutter)
              } else {
                ForEach(GitService.getInstance().statusItems, (it: GitStatusItem) => {
                  Row({ space: 8 }) {
                    Text(it.status.substring(0, 1).toUpperCase())
                      .fontSize(11)
                      .fontColor(this.statusColor(it.status))
                      .width(14)
                    Text(it.path)
                      .fontSize(12)
                      .fontColor(IdeTheme.palette().mutedForeground)
                      .fontFamily('monospace')
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('100%')
                  .padding({ top: 3, bottom: 3 })
                }, (it: GitStatusItem) => `${it.path}-${it.status}`)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width(this.panelWidth > 0 ? this.panelWidth : '100%')
    .height('100%')
    .backgroundColor(IdeTheme.palette().sidebar)
    .border({ width: { right: 1 }, color: IdeTheme.palette().border })
  }
}
