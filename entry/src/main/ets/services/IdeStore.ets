import {
  EditorTab, FileNode, BottomPanelTab, ActivityId, ProblemItem, SearchHit, QuickOpenItem
} from '../models/FileNode';
import { WorkspaceService } from './WorkspaceService';
import { SettingsStore } from './SettingsStore';
import { LintService } from './LintService';
import { promptAction } from '@kit.ArkUI';
import { RemoteSession } from './remote/RemoteSession';

/**
 * IDE 会话状态：标签、活动栏、底栏、选中文件、搜索、命令面板。
 * UI 通过 @StorageLink('ideRev') 订阅。
 */
export class IdeStore {
  private static instance: IdeStore = new IdeStore();

  tabs: EditorTab[] = [];
  activeTabId: string = '';
  tree: FileNode[] = [];
  selectedPath: string = '';
  activity: ActivityId = 'explorer';
  bottomTab: BottomPanelTab = 'terminal';
  phoneNav: string = 'editor'; // files | editor | terminal | settings
  terminalLines: string[] = [];
  outputLines: string[] = [];
  problems: ProblemItem[] = [];
  showRenameDialog: boolean = false;
  showNewFileDialog: boolean = false;
  dialogInput: string = '';
  dialogTargetPath: string = '';

  // 搜索
  searchQuery: string = '';
  searchHits: SearchHit[] = [];
  searchBusy: boolean = false;

  // 命令面板
  commandPaletteOpen: boolean = false;
  commandQuery: string = '';
  commandItems: QuickOpenItem[] = [];

  // 编辑器命令队列（由 MonacoWebEditor 消费）
  pendingEditorCmd: string = ''; // find | replace | reveal:line:col
  editorCmdRev: number = 0;

  // 欢迎 / 外部变更
  showWelcome: boolean = false;
  externalChangePath: string = '';

  private watchTimer: number = -1;
  private treeWatchTimer: number = -1;

  static getInstance(): IdeStore {
    return IdeStore.instance;
  }

  private bump(): void {
    try {
      const cur = AppStorage.get<number>('ideRev') ?? 0;
      AppStorage.setOrCreate('ideRev', cur + 1);
    } catch (_e) {
      // ignore
    }
  }

  private bumpEditorCmd(): void {
    this.editorCmdRev += 1;
    try {
      AppStorage.setOrCreate('editorCmdRev', this.editorCmdRev);
    } catch (_e) {
      // ignore
    }
  }

  bootstrap(): void {
    const ws = WorkspaceService.getInstance();
    this.tree = ws.refreshTree();
    this.terminalLines = [
      '# Scheme B：优先远程 Agent PTY；本地沙箱/原生 PTY 为次要',
      `local root: ${ws.getRootPath()}`,
      '# 欢迎页主 CTA：打开远程文件夹'
    ];
    this.outputLines = [
      '[Info] 鸿蒙原生IDE 已启动（Scheme B / B1+B2）',
      '[Info] 默认请「打开远程文件夹」；本地示例为次要演示'
    ];
    this.problems = [];
    SettingsStore.getInstance().pushRecentRoot(ws.getRootPath());
    // Scheme B：默认欢迎页，主 CTA 打开远程
    this.showWelcome = true;
    this.tabs = [];
    this.activeTabId = '';
    this.selectedPath = '';
    this.startWatchers();
    this.bump();
  }

  /** Called after remote session connects */
  bumpFromRemote(): void {
    this.showWelcome = false;
    this.bump();
  }

  openRemoteFolderDialogFlag(): void {
    // UI owns the dialog; this helper just switches activity
    this.showWelcome = true;
    this.bump();
  }

  startWatchers(): void {
    this.stopWatchers();
    // 轮询打开文件的外部变更（约 2.5s）
    this.watchTimer = setInterval(() => {
      this.pollOpenFiles();
    }, 2500) as number;
    // 定期刷新树（约 8s）
    this.treeWatchTimer = setInterval(() => {
      this.refreshTreeQuiet();
    }, 8000) as number;
  }

  stopWatchers(): void {
    if (this.watchTimer >= 0) {
      clearInterval(this.watchTimer);
      this.watchTimer = -1;
    }
    if (this.treeWatchTimer >= 0) {
      clearInterval(this.treeWatchTimer);
      this.treeWatchTimer = -1;
    }
  }

  private refreshTreeQuiet(): void {
    if (RemoteSession.getInstance().isRemote()) {
      RemoteSession.getInstance().refreshTree().catch(() => {});
      return;
    }
    this.tree = WorkspaceService.getInstance().refreshTree();
    this.bump();
  }

  private pollOpenFiles(): void {
    const ws = WorkspaceService.getInstance();
    for (let i = 0; i < this.tabs.length; i++) {
      const tab = this.tabs[i];
      const mtime = ws.getMtime(tab.path);
      if (!mtime) {
        continue;
      }
      if (tab.diskMtime === 0) {
        tab.diskMtime = mtime;
        continue;
      }
      if (mtime > tab.diskMtime + 50) {
        // 外部变更
        if (tab.dirty) {
          if (this.externalChangePath !== tab.path) {
            this.externalChangePath = tab.path;
            this.promptExternalChange(tab);
          }
        } else {
          // 未脏：自动重载
          const content = ws.readFile(tab.path);
          tab.content = content;
          tab.savedContent = content;
          tab.diskMtime = mtime;
          this.appendOutput(`[Watch] 已重载 ${tab.name}`);
          this.recomputeProblems();
          this.bump();
        }
      }
    }
  }

  private promptExternalChange(tab: EditorTab): void {
    promptAction.showDialog({
      title: '文件已在外部修改',
      message: `${tab.name} 已在磁盘上变更，且本地有未保存修改。重新加载将丢弃本地更改。`,
      buttons: [
        { text: '保留本地', color: '#a1a1aa' },
        { text: '重新加载', color: '#f87171' }
      ]
    }).then((res) => {
      this.externalChangePath = '';
      if (res.index === 1) {
        const ws = WorkspaceService.getInstance();
        const content = ws.readFile(tab.path);
        tab.content = content;
        tab.savedContent = content;
        tab.dirty = false;
        tab.diskMtime = ws.getMtime(tab.path);
        this.appendOutput(`[Watch] 已重载 ${tab.name}`);
        this.recomputeProblems();
        this.bump();
      } else {
        // 保留本地：更新基线 mtime，避免反复弹窗
        tab.diskMtime = WorkspaceService.getInstance().getMtime(tab.path);
      }
    }).catch(() => {
      this.externalChangePath = '';
    });
  }

  refreshTree(): void {
    if (RemoteSession.getInstance().isRemote()) {
      RemoteSession.getInstance().refreshTree().then(() => this.bump()).catch((e: Error) => {
        this.appendOutput(`[Remote] 刷新树失败: ${e.message}`);
      });
      return;
    }
    this.tree = WorkspaceService.getInstance().refreshTree();
    this.bump();
  }

  setActivity(id: ActivityId): void {
    this.activity = id;
    this.bump();
  }

  setBottomTab(tab: BottomPanelTab): void {
    this.bottomTab = tab;
    this.bump();
  }

  setPhoneNav(nav: string): void {
    this.phoneNav = nav;
    this.bump();
  }

  toggleFolder(node: FileNode): void {
    if (!node.isDirectory) {
      return;
    }
    node.expanded = !node.expanded;
    if (node.expanded && node.children.length === 0) {
      this.refreshTree();
      return;
    }
    this.bump();
  }

  openFile(path: string, line: number = 0, column: number = 1): void {
    if (RemoteSession.getInstance().isRemote()) {
      RemoteSession.getInstance().openRemoteFile(path).then(() => {
        this.phoneNav = 'editor';
        if (line > 0) {
          this.requestReveal(line, column);
        }
        this.bump();
      }).catch((e: Error) => {
        this.appendOutput(`[Remote] 打开失败: ${e.message}`);
      });
      return;
    }
    const ws = WorkspaceService.getInstance();
    const existing = this.tabs.find((t: EditorTab) => t.path === path);
    if (existing) {
      this.activeTabId = existing.id;
      this.selectedPath = path;
      this.showWelcome = false;
      this.phoneNav = 'editor';
      if (line > 0) {
        this.requestReveal(line, column);
      }
      this.bump();
      return;
    }
    const name = path.substring(path.lastIndexOf('/') + 1);
    const content = ws.readFile(path);
    const lang = ws.detectLanguage(name);
    const tab = new EditorTab(path, name, content, lang);
    tab.diskMtime = ws.getMtime(path);
    this.tabs.push(tab);
    this.activeTabId = tab.id;
    this.selectedPath = path;
    this.phoneNav = 'editor';
    this.showWelcome = false;
    this.recomputeProblems();
    if (line > 0) {
      this.requestReveal(line, column);
    }
    this.bump();
  }

  closeTab(id: string): void {
    const idx = this.tabs.findIndex((t: EditorTab) => t.id === id);
    if (idx < 0) {
      return;
    }
    this.tabs.splice(idx, 1);
    if (this.activeTabId === id) {
      if (this.tabs.length > 0) {
        const next = this.tabs[Math.min(idx, this.tabs.length - 1)];
        this.activeTabId = next.id;
        this.selectedPath = next.path;
      } else {
        this.activeTabId = '';
        this.selectedPath = '';
        this.showWelcome = true;
      }
    }
    this.recomputeProblems();
    this.bump();
  }

  activateTab(id: string): void {
    const tab = this.tabs.find((t: EditorTab) => t.id === id);
    if (!tab) {
      return;
    }
    this.activeTabId = id;
    this.selectedPath = tab.path;
    this.showWelcome = false;
    this.bump();
  }

  getActiveTab(): EditorTab | null {
    return this.tabs.find((t: EditorTab) => t.id === this.activeTabId) ?? null;
  }

  activeTabName(fallback: string): string {
    const tab = this.getActiveTab();
    return tab ? tab.name : fallback;
  }

  activeTabDirty(): boolean {
    const tab = this.getActiveTab();
    return tab ? tab.dirty : false;
  }

  onEditorChange(value: string): void {
    const tab = this.getActiveTab();
    if (!tab) {
      return;
    }
    tab.markDirty(value);
    this.recomputeProblems();
    this.bump();
  }

  recomputeProblems(): void {
    this.problems = LintService.lintTabs(this.tabs);
  }

  saveActive(): boolean {
    const tab = this.getActiveTab();
    if (!tab) {
      return false;
    }
    if (RemoteSession.getInstance().isRemote()) {
      RemoteSession.getInstance().saveRemoteActive().then(() => {
        this.recomputeProblems();
        this.bump();
      }).catch((e: Error) => {
        this.appendOutput(`[Save/Remote] 失败: ${e.message}`);
      });
      return true;
    }
    const ws = WorkspaceService.getInstance();
    ws.writeFile(tab.path, tab.content);
    tab.markSaved();
    tab.diskMtime = ws.getMtime(tab.path);
    this.appendOutput(`[Save] ${tab.name}`);
    this.recomputeProblems();
    this.bump();
    return true;
  }

  saveAll(): void {
    const ws = WorkspaceService.getInstance();
    for (let i = 0; i < this.tabs.length; i++) {
      const t = this.tabs[i];
      if (t.dirty) {
        ws.writeFile(t.path, t.content);
        t.markSaved();
        t.diskMtime = ws.getMtime(t.path);
      }
    }
    this.appendOutput('[Save] 全部已保存');
    this.recomputeProblems();
    this.bump();
  }

  appendTerminal(line: string): void {
    this.terminalLines.push(line);
    if (this.terminalLines.length > 200) {
      this.terminalLines = this.terminalLines.slice(-150);
    }
    this.bump();
  }

  appendOutput(line: string): void {
    this.outputLines.push(line);
    if (this.outputLines.length > 200) {
      this.outputLines = this.outputLines.slice(-150);
    }
    this.bump();
  }

  createFileInSelection(name: string): void {
    const rs = RemoteSession.getInstance();
    if (rs.isRemote()) {
      let parent = rs.remoteFs.rootPath;
      if (this.selectedPath) {
        parent = this.selectedPath.substring(0, this.selectedPath.lastIndexOf('/'));
      }
      const path = `${parent}/${name}`;
      rs.remoteFs.write(path, `// ${name}\n`).then(() => {
        this.refreshTree();
        this.openFile(path);
        this.appendOutput(`[New/Remote] ${name}`);
      });
      return;
    }
    const ws = WorkspaceService.getInstance();
    let parent = ws.getRootPath();
    if (this.selectedPath) {
      try {
        parent = this.selectedPath.substring(0, this.selectedPath.lastIndexOf('/'));
      } catch (_e) {
        parent = ws.getRootPath();
      }
    }
    const path = ws.createFile(parent, name, `// ${name}\n`);
    this.refreshTree();
    this.openFile(path);
    this.appendOutput(`[New] ${name}`);
  }

  createFolderInSelection(name: string): void {
    const rs = RemoteSession.getInstance();
    if (rs.isRemote()) {
      let parent = rs.remoteFs.rootPath;
      if (this.selectedPath) {
        parent = this.selectedPath.substring(0, this.selectedPath.lastIndexOf('/'));
      }
      const path = `${parent}/${name}`;
      rs.remoteFs.mkdir(path).then(() => {
        this.refreshTree();
        this.appendOutput(`[NewFolder/Remote] ${name}`);
      });
      return;
    }
    const ws = WorkspaceService.getInstance();
    let parent = ws.getRootPath();
    if (this.selectedPath) {
      parent = this.selectedPath.substring(0, this.selectedPath.lastIndexOf('/'));
    }
    ws.createFolder(parent, name);
    this.refreshTree();
    this.appendOutput(`[NewFolder] ${name}`);
  }

  renameSelected(newName: string): void {
    if (!this.selectedPath || !newName) {
      return;
    }
    const old = this.selectedPath;
    const parent = old.substring(0, old.lastIndexOf('/'));
    const neu = `${parent}/${newName}`;
    const rs = RemoteSession.getInstance();
    if (rs.isRemote()) {
      rs.remoteFs.rename(old, neu).then(() => {
        for (let i = 0; i < this.tabs.length; i++) {
          if (this.tabs[i].path === old) {
            this.tabs[i].path = neu;
            this.tabs[i].id = neu;
            this.tabs[i].name = newName;
            if (this.activeTabId === old) {
              this.activeTabId = neu;
            }
          }
        }
        this.selectedPath = neu;
        this.refreshTree();
        this.appendOutput(`[Rename/Remote] ${newName}`);
      });
      return;
    }
    const renamed = WorkspaceService.getInstance().rename(old, newName);
    for (let i = 0; i < this.tabs.length; i++) {
      if (this.tabs[i].path === old) {
        this.tabs[i].path = renamed;
        this.tabs[i].id = renamed;
        this.tabs[i].name = newName;
        if (this.activeTabId === old) {
          this.activeTabId = renamed;
        }
      }
    }
    this.selectedPath = renamed;
    this.refreshTree();
    this.appendOutput(`[Rename] ${newName}`);
  }

  deleteSelected(): void {
    if (!this.selectedPath) {
      return;
    }
    const path = this.selectedPath;
    this.tabs = this.tabs.filter((t: EditorTab) => t.path.indexOf(path) !== 0);
    if (!this.tabs.find((t: EditorTab) => t.id === this.activeTabId)) {
      this.activeTabId = this.tabs.length > 0 ? this.tabs[0].id : '';
      const at = this.getActiveTab();
      this.selectedPath = at ? at.path : '';
      if (!at) {
        this.showWelcome = true;
      }
    }
    const rs = RemoteSession.getInstance();
    if (rs.isRemote()) {
      rs.remoteFs.remove(path, true).then(() => {
        this.refreshTree();
        this.recomputeProblems();
        this.appendOutput(`[Delete/Remote] ${path}`);
      });
      return;
    }
    WorkspaceService.getInstance().deletePath(path);
    this.refreshTree();
    this.recomputeProblems();
    this.appendOutput(`[Delete] ${path}`);
  }

  flatTree(): FileNode[] {
    return WorkspaceService.getInstance().flatten(this.tree);
  }

  // —— 搜索 ——
  setSearchQuery(q: string): void {
    this.searchQuery = q;
    this.bump();
  }

  runSearch(): void {
    const q = this.searchQuery.trim();
    if (!q) {
      this.searchHits = [];
      this.bump();
      return;
    }
    this.searchBusy = true;
    this.bump();
    const rs = RemoteSession.getInstance();
    if (rs.isRemote()) {
      rs.search(q, 80).then((hits: Object[]) => {
        const mapped: SearchHit[] = [];
        for (let i = 0; i < hits.length; i++) {
          const h = hits[i] as Record<string, Object>;
          mapped.push(new SearchHit(
            String(h['path'] ?? ''),
            String(h['relPath'] ?? h['path'] ?? ''),
            Number(h['line'] ?? 1),
            1,
            String(h['preview'] ?? '')
          ));
        }
        this.searchHits = mapped;
        this.searchBusy = false;
        this.appendOutput(`[Search/Remote] 「${q}」→ ${mapped.length} 条`);
        this.bump();
      }).catch((e: Error) => {
        this.searchBusy = false;
        this.appendOutput(`[Search/Remote] 失败: ${e.message}`);
        this.bump();
      });
      return;
    }
    this.searchHits = WorkspaceService.getInstance().searchInFiles(q, 80);
    this.searchBusy = false;
    this.appendOutput(`[Search] 「${q}」→ ${this.searchHits.length} 条`);
    this.bump();
  }

  openSearchHit(hit: SearchHit): void {
    this.openFile(hit.path, hit.line, hit.column);
  }

  openProblem(p: ProblemItem): void {
    if (p.path) {
      this.openFile(p.path, p.line, p.column);
    } else {
      // 按文件名在标签中匹配
      const tab = this.tabs.find((t: EditorTab) => t.name === p.file || t.path.endsWith(p.file));
      if (tab) {
        this.openFile(tab.path, p.line, p.column);
      }
    }
    this.setBottomTab('problems');
  }

  // —— 编辑器命令 ——
  requestFind(): void {
    this.pendingEditorCmd = 'find';
    this.bumpEditorCmd();
  }

  requestReplace(): void {
    this.pendingEditorCmd = 'replace';
    this.bumpEditorCmd();
  }

  requestReveal(line: number, column: number = 1): void {
    this.pendingEditorCmd = `reveal:${line}:${column}`;
    this.bumpEditorCmd();
  }

  consumeEditorCmd(): string {
    const c = this.pendingEditorCmd;
    this.pendingEditorCmd = '';
    return c;
  }

  // —— 命令面板 ——
  openCommandPalette(): void {
    this.commandPaletteOpen = true;
    this.commandQuery = '';
    this.rebuildCommandItems('');
    this.bump();
  }

  closeCommandPalette(): void {
    this.commandPaletteOpen = false;
    this.commandQuery = '';
    this.commandItems = [];
    this.bump();
  }

  setCommandQuery(q: string): void {
    this.commandQuery = q;
    this.rebuildCommandItems(q);
    this.bump();
  }

  private fuzzyScore(query: string, target: string): number {
    if (!query) {
      return 1;
    }
    const q = query.toLowerCase();
    const t = target.toLowerCase();
    if (t.indexOf(q) >= 0) {
      return 100 - t.indexOf(q);
    }
    // 子序列
    let qi = 0;
    let score = 0;
    for (let i = 0; i < t.length && qi < q.length; i++) {
      if (t.charAt(i) === q.charAt(qi)) {
        score += 2;
        qi++;
      }
    }
    return qi === q.length ? score : 0;
  }

  private rebuildCommandItems(q: string): void {
    const ws = WorkspaceService.getInstance();
    const files = ws.listAllFiles(400);
    const items: QuickOpenItem[] = [];
    for (let i = 0; i < files.length; i++) {
      const path = files[i];
      const rel = ws.relativePath(path);
      const name = path.substring(path.lastIndexOf('/') + 1);
      const score = Math.max(this.fuzzyScore(q, name), this.fuzzyScore(q, rel));
      if (!q || score > 0) {
        items.push(new QuickOpenItem(path, rel, name, score));
      }
    }
    items.sort((a: QuickOpenItem, b: QuickOpenItem) => {
      if (b.score !== a.score) {
        return b.score - a.score;
      }
      return a.relPath.localeCompare(b.relPath);
    });
    this.commandItems = items.slice(0, 40);
  }

  pickCommandItem(item: QuickOpenItem): void {
    this.closeCommandPalette();
    this.openFile(item.path);
  }

  // —— 欢迎 ——
  goWelcome(): void {
    // 关闭全部标签进入欢迎
    this.tabs = [];
    this.activeTabId = '';
    this.selectedPath = '';
    this.showWelcome = true;
    this.recomputeProblems();
    this.bump();
  }

  openSampleProject(): void {
    const ws = WorkspaceService.getInstance();
    ws.reseedSample().then(() => {
      this.refreshTree();
      SettingsStore.getInstance().pushRecentRoot(ws.getRootPath());
      const indexAbs = `${ws.getRootPath()}/entry/src/main/ets/pages/Index.ets`;
      this.openFile(indexAbs);
      this.appendOutput('[Welcome] 已打开示例工程 HelloWorld');
    });
  }

  openRecentRoot(root: string): void {
    // MVP：仅一个沙箱根；若匹配则刷新打开
    const ws = WorkspaceService.getInstance();
    if (root === ws.getRootPath()) {
      this.refreshTree();
      const indexAbs = `${ws.getRootPath()}/entry/src/main/ets/pages/Index.ets`;
      this.openFile(indexAbs);
      SettingsStore.getInstance().pushRecentRoot(root);
    } else {
      this.appendOutput(`[Welcome] 最近项目暂仅支持当前沙箱根：${ws.getRootPath()}`);
      this.refreshTree();
      this.showWelcome = false;
      this.openFile(`${ws.getRootPath()}/entry/src/main/ets/pages/Index.ets`);
    }
  }
}
