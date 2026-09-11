import { AgentClient } from './AgentClient';
import { RemoteFs } from './RemoteFs';
import { SshDeployService, RemoteConnectOptions, DeployStatus } from './SshDeployService';
import { IdeStore } from '../IdeStore';
import { EditorTab } from '../../models/FileNode';
import { LocalTerminalService } from '../LocalTerminalService';

export const EXPECTED_AGENT_VERSION: string = '0.2.0';

export type SessionMode = 'local' | 'remote';

/**
 * Orchestrates SSH deploy + agent WS session (Scheme B / B1+B2).
 * Features: watch→tree refresh, auto-reconnect+resume, local drafts, search/git/task RPC.
 */
export class RemoteSession {
  private static instance: RemoteSession = new RemoteSession();

  mode: SessionMode = 'local';
  client: AgentClient = new AgentClient();
  remoteFs: RemoteFs = new RemoteFs(this.client);
  options: RemoteConnectOptions | null = null;
  agentVersion: string = '';
  agentOs: string = '';
  agentArch: string = '';
  agentPid: number = 0;
  sessionToken: string = '';
  statusText: string = '';
  deployLog: string[] = [];
  reconnectAttempt: number = 0;
  private ptyId: string = '';
  private watchId: string = '';
  private handlersAttached: boolean = false;
  private reconnectTimer: number = -1;
  private intentionalDisconnect: boolean = false;
  /** Local drafts for unsaved remote files while disconnected: path → content */
  drafts: Map<string, string> = new Map();

  static getInstance(): RemoteSession {
    return RemoteSession.instance;
  }

  isRemote(): boolean {
    return this.mode === 'remote' && this.client.connected;
  }

  statusBarLabel(): string {
    if (!this.options) {
      return '';
    }
    if (this.mode === 'remote' && this.client.connected) {
      return `SSH: ${this.options.user}@${this.options.host}`;
    }
    if (this.mode === 'remote') {
      return `SSH(重连中): ${this.options.user}@${this.options.host}`;
    }
    return '';
  }

  private bump(): void {
    try {
      const cur = AppStorage.get<number>('remoteSessionRev') ?? 0;
      AppStorage.setOrCreate('remoteSessionRev', cur + 1);
      const ide = AppStorage.get<number>('ideRev') ?? 0;
      AppStorage.setOrCreate('ideRev', ide + 1);
    } catch (_e) {
      // ignore
    }
  }

  private log(msg: string): void {
    this.deployLog.push(msg);
    this.statusText = msg;
    IdeStore.getInstance().appendOutput(`[Remote] ${msg}`);
    this.bump();
  }

  async connect(opts: RemoteConnectOptions): Promise<boolean> {
    this.intentionalDisconnect = false;
    this.options = opts;
    this.deployLog = [];
    this.reconnectAttempt = 0;
    this.log('开始连接远程…');

    const deploy = SshDeployService.getInstance();
    const steps = await deploy.deployAndForward(opts, (st: DeployStatus) => {
      this.log(st.message);
    });
    if (!steps.ok) {
      this.log(`部署未完成：${steps.message}（若本机已 LocalForward 将继续连 Agent）`);
    }

    const wsUrl = deploy.wsUrl(opts);
    const ok = await this.connectWsAndHello(wsUrl, opts.agentToken, false);
    if (!ok) {
      this.mode = 'local';
      this.bump();
      return false;
    }

    this.remoteFs.setRoot(opts.remotePath);
    this.mode = 'remote';
    this.attachNotifications();
    await this.startWatch(opts.remotePath);
    this.restoreDrafts();

    try {
      LocalTerminalService.getInstance().switchToRemoteIfNeeded();
    } catch (_e) {
      // ignore
    }

    const store = IdeStore.getInstance();
    store.tabs = [];
    store.activeTabId = '';
    try {
      const tree = await this.remoteFs.buildTree(opts.remotePath, 2);
      store.tree = tree;
      store.showWelcome = false;
      store.appendOutput(`[Remote] 已打开远程文件夹 ${opts.remotePath}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.log(`列目录失败：${msg}`);
    }
    this.bump();
    return true;
  }

  private async connectWsAndHello(wsUrl: string, token: string, resume: boolean): Promise<boolean> {
    this.log(`连接 Agent ${wsUrl}${resume ? ' (resume)' : ''}`);
    try {
      await this.client.connect(wsUrl, token);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.log(`WebSocket 失败：${msg}`);
      return false;
    }

    try {
      const helloParams: Record<string, Object> = {};
      if (resume && this.sessionToken) {
        helloParams['sessionToken'] = this.sessionToken;
      }
      const hello = await this.client.request('session.hello', helloParams) as Record<string, Object>;
      this.agentVersion = String(hello['version'] ?? '');
      this.agentOs = String(hello['os'] ?? '');
      this.agentArch = String(hello['arch'] ?? '');
      this.agentPid = Number(hello['pid'] ?? 0);
      this.sessionToken = String(hello['session_token'] ?? hello['sessionToken'] ?? this.sessionToken);
      const resumed = Boolean(hello['resumed']);
      this.log(
        `hello ok · v${this.agentVersion} ${this.agentOs}/${this.agentArch} pid=${this.agentPid}` +
          (resumed ? ' (resumed)' : '')
      );

      if (this.agentVersion !== EXPECTED_AGENT_VERSION && this.options) {
        this.log(`版本不匹配：远端 ${this.agentVersion} ≠ 期望 ${EXPECTED_AGENT_VERSION}`);
        const deploy = SshDeployService.getInstance();
        const replaced = await deploy.replaceBinaryAndRestart(this.options, (st: DeployStatus) => {
          this.log(st.message);
        });
        if (replaced.ok) {
          await this.client.disconnect();
          await this.client.connect(wsUrl, token);
          const hello2 = await this.client.request('session.hello', {}) as Record<string, Object>;
          this.agentVersion = String(hello2['version'] ?? '');
          this.sessionToken = String(hello2['session_token'] ?? '');
          this.log(`替换后 hello · v${this.agentVersion}`);
        } else {
          this.log(`替换需主机助手：${replaced.message}；继续使用当前版本`);
        }
      }
      return true;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.log(`session.hello 失败：${msg}`);
      await this.client.disconnect();
      return false;
    }
  }

  /** Save unsaved remote tab content to local drafts (for disconnect). */
  snapshotDrafts(): void {
    const store = IdeStore.getInstance();
    for (let i = 0; i < store.tabs.length; i++) {
      const tab = store.tabs[i];
      if (tab.dirty) {
        this.drafts.set(tab.path, tab.content);
      }
    }
  }

  private restoreDrafts(): void {
    if (this.drafts.size === 0) {
      return;
    }
    this.log(`恢复 ${this.drafts.size} 个本地草稿（断线期间未保存）`);
    const store = IdeStore.getInstance();
    this.drafts.forEach((content: string, path: string) => {
      const tab = store.tabs.find((t: EditorTab) => t.path === path);
      if (tab) {
        tab.content = content;
        tab.dirty = true;
      }
    });
  }

  private attachNotifications(): void {
    if (this.handlersAttached) {
      return;
    }
    this.handlersAttached = true;
    this.client.onNotification((method: string, params: Object) => {
      if (method === 'pty.data') {
        const p = params as Record<string, Object>;
        const data = String(p['data'] ?? '');
        try {
          AppStorage.setOrCreate('remotePtyChunk', data);
          const rev = AppStorage.get<number>('remotePtyRev') ?? 0;
          AppStorage.setOrCreate('remotePtyRev', rev + 1);
        } catch (_e) {
          // ignore
        }
      } else if (method === 'fs.changed') {
        this.onFsChanged(params as Record<string, Object>);
      } else if (method === 'task.output') {
        const p = params as Record<string, Object>;
        IdeStore.getInstance().appendOutput(String(p['data'] ?? ''));
        try {
          const rev = AppStorage.get<number>('buildRev') ?? 0;
          AppStorage.setOrCreate('buildRev', rev + 1);
          AppStorage.setOrCreate('remoteTaskChunk', String(p['data'] ?? ''));
        } catch (_e) {
          // ignore
        }
      } else if (method === 'task.exit') {
        const p = params as Record<string, Object>;
        IdeStore.getInstance().appendOutput(`[Task] exit code=${p['code']}`);
        try {
          const rev = AppStorage.get<number>('buildRev') ?? 0;
          AppStorage.setOrCreate('buildRev', rev + 1);
        } catch (_e) {
          // ignore
        }
      }
    });
    this.client.onClose(() => {
      if (this.intentionalDisconnect) {
        return;
      }
      this.log('WebSocket 断开，准备自动重连…');
      this.snapshotDrafts();
      this.scheduleReconnect();
    });
  }

  private onFsChanged(params: Record<string, Object>): void {
    const paths = (params['paths'] as string[]) ?? [];
    IdeStore.getInstance().appendOutput(`[Watch] ${params['kind']} ${paths.join(', ')}`);
    this.refreshTree().catch(() => {});
    // Prompt reload for dirty tabs whose path changed
    const store = IdeStore.getInstance();
    for (let i = 0; i < store.tabs.length; i++) {
      const tab = store.tabs[i];
      for (let j = 0; j < paths.length; j++) {
        if (tab.path === paths[j] && !tab.dirty) {
          store.externalChangePath = tab.path;
          this.remoteFs.read(tab.path).then((content: string) => {
            tab.content = content;
            tab.markSaved();
            store.appendOutput(`[Watch] 已重载 ${tab.name}`);
            this.bump();
          }).catch(() => {});
        } else if (tab.path === paths[j] && tab.dirty) {
          store.externalChangePath = tab.path;
          store.appendOutput(`[Watch] ${tab.name} 远端变更且本地有未保存修改 — 请手动重载或保存`);
        }
      }
    }
    this.bump();
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
    }
    const attempt = this.reconnectAttempt;
    const delay = Math.min(30000, 1000 * Math.pow(2, attempt));
    this.reconnectAttempt = attempt + 1;
    this.log(`将在 ${delay}ms 后重连（第 ${this.reconnectAttempt} 次）…`);
    this.reconnectTimer = setTimeout(() => {
      this.tryReconnect();
    }, delay) as number;
  }

  private async tryReconnect(): Promise<void> {
    if (!this.options || this.intentionalDisconnect) {
      return;
    }
    const wsUrl = SshDeployService.getInstance().wsUrl(this.options);
    const ok = await this.connectWsAndHello(wsUrl, this.options.agentToken, true);
    if (ok) {
      this.reconnectAttempt = 0;
      this.mode = 'remote';
      this.attachNotifications();
      await this.startWatch(this.options.remotePath);
      this.restoreDrafts();
      this.log('重连成功');
      this.bump();
    } else {
      this.scheduleReconnect();
    }
  }

  async startWatch(path: string): Promise<void> {
    if (this.watchId) {
      try {
        await this.client.request('fs.unwatch', { watchId: this.watchId });
      } catch (_e) {
        // ignore
      }
      this.watchId = '';
    }
    try {
      const res = await this.client.request('fs.watch', { path, recursive: true }) as Record<string, Object>;
      this.watchId = String(res['watchId'] ?? '');
      this.log(`已监视 ${path} (${this.watchId})`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.log(`fs.watch 失败：${msg}`);
    }
  }

  async disconnect(): Promise<void> {
    this.intentionalDisconnect = true;
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    this.snapshotDrafts();
    if (this.watchId) {
      try {
        await this.client.request('fs.unwatch', { watchId: this.watchId });
      } catch (_e) {
        // ignore
      }
      this.watchId = '';
    }
    if (this.ptyId) {
      try {
        await this.client.request('pty.close', { ptyId: this.ptyId });
      } catch (_e) {
        // ignore
      }
      this.ptyId = '';
    }
    await this.client.disconnect();
    this.mode = 'local';
    this.options = null;
    this.statusText = '已断开';
    IdeStore.getInstance().appendOutput('[Remote] 已断开远程会话');
    this.bump();
  }

  async refreshTree(): Promise<void> {
    if (!this.options || this.mode !== 'remote') {
      return;
    }
    try {
      const tree = await this.remoteFs.buildTree(this.options.remotePath, 2);
      IdeStore.getInstance().tree = tree;
      this.bump();
    } catch (_e) {
      // ignore
    }
  }

  async openRemoteFile(path: string): Promise<void> {
    const store = IdeStore.getInstance();
    const existing = store.tabs.find((t: EditorTab) => t.path === path);
    if (existing) {
      store.activeTabId = existing.id;
      store.selectedPath = path;
      store.showWelcome = false;
      this.bump();
      return;
    }
    let content = '';
    if (this.drafts.has(path) && !this.client.connected) {
      content = this.drafts.get(path) as string;
    } else {
      content = await this.remoteFs.read(path);
      if (this.drafts.has(path)) {
        // Prefer draft if newer unsaved
        content = this.drafts.get(path) as string;
      }
    }
    const name = path.substring(path.lastIndexOf('/') + 1);
    const lang = this.remoteFs.detectLanguage(name);
    const tab = new EditorTab(path, name, content, lang);
    if (this.drafts.has(path)) {
      tab.dirty = true;
    }
    tab.diskMtime = await this.remoteFs.getMtime(path);
    store.tabs.push(tab);
    store.activeTabId = tab.id;
    store.selectedPath = path;
    store.showWelcome = false;
    store.recomputeProblems();
    this.bump();
  }

  async saveRemoteActive(): Promise<boolean> {
    const store = IdeStore.getInstance();
    const tab = store.getActiveTab();
    if (!tab || this.mode !== 'remote') {
      return false;
    }
    if (!this.client.connected) {
      this.drafts.set(tab.path, tab.content);
      store.appendOutput(`[Draft] 离线保存草稿 ${tab.name}`);
      this.bump();
      return false;
    }
    await this.remoteFs.write(tab.path, tab.content);
    tab.markSaved();
    this.drafts.delete(tab.path);
    tab.diskMtime = await this.remoteFs.getMtime(tab.path);
    store.appendOutput(`[Save/Remote] ${tab.name}`);
    this.bump();
    return true;
  }

  async search(query: string, maxHits: number = 80): Promise<Object[]> {
    if (!this.options || !this.client.connected) {
      return [];
    }
    const res = await this.client.request('fs.search', {
      path: this.options.remotePath,
      query,
      maxHits,
      caseInsensitive: true
    }) as Record<string, Object>;
    return (res['hits'] as Object[]) ?? [];
  }

  async gitStatus(): Promise<Record<string, Object>> {
    if (!this.options || !this.client.connected) {
      return { items: [], clean: true };
    }
    return await this.client.request('git.status', { path: this.options.remotePath }) as Record<string, Object>;
  }

  async gitDiff(): Promise<Record<string, Object>> {
    if (!this.options || !this.client.connected) {
      return { files: [] };
    }
    return await this.client.request('git.diff', { path: this.options.remotePath }) as Record<string, Object>;
  }

  async runTask(command: string): Promise<string> {
    if (!this.options || !this.client.connected) {
      throw new Error('not connected');
    }
    const res = await this.client.request('task.run', {
      command,
      cwd: this.options.remotePath,
      shell: true
    }) as Record<string, Object>;
    return String(res['taskId'] ?? '');
  }

  async killTask(taskId: string): Promise<void> {
    await this.client.request('task.kill', { taskId });
  }

  async openPty(cols: number, rows: number, cwd?: string): Promise<string> {
    const res = await this.client.request('pty.open', {
      cols,
      rows,
      cwd: cwd ? cwd : (this.options != null ? this.options.remotePath : ''),
      shell: ''
    }) as Record<string, Object>;
    this.ptyId = String(res['ptyId'] ?? '');
    this.bump();
    return this.ptyId;
  }

  async writePty(data: string): Promise<void> {
    if (!this.ptyId) {
      return;
    }
    await this.client.request('pty.write', { ptyId: this.ptyId, data, encoding: 'utf8' });
  }

  async resizePty(cols: number, rows: number): Promise<void> {
    if (!this.ptyId) {
      return;
    }
    await this.client.request('pty.resize', { ptyId: this.ptyId, cols, rows });
  }

  async closePty(): Promise<void> {
    if (!this.ptyId) {
      return;
    }
    try {
      await this.client.request('pty.close', { ptyId: this.ptyId });
    } catch (_e) {
      // ignore
    }
    this.ptyId = '';
  }

  getPtyId(): string {
    return this.ptyId;
  }
}
