/**
 * ArkTS facade for libhm_git.so (libgit2 NAPI).
 * Stub mode returns ENOSYS until HM_GIT2_ROOT is set at native build time.
 */
import hmGit from 'libhm_git.so';
import { WorkspaceService } from './WorkspaceService';
import { RemoteSession } from './remote/RemoteSession';

export interface GitResult {
  code: number;
  err: string;
  message: string;
  data: string;
  ok: boolean;
}

export interface GitStatusItem {
  path: string;
  status: string;
}

export class GitService {
  private static instance: GitService = new GitService();
  repoOpen: boolean = false;
  branch: string = '';
  statusItems: GitStatusItem[] = [];
  lastError: string = '';
  libgit2Linked: boolean = false;
  /** When connected to agent, SCM comes from git.status RPC */
  remoteSource: boolean = false;

  static getInstance(): GitService {
    return GitService.instance;
  }

  private bump(): void {
    try {
      const cur = AppStorage.get<number>('scmRev') ?? 0;
      AppStorage.setOrCreate('scmRev', cur + 1);
    } catch (_e) {
      // ignore
    }
  }

  private wrap(r: Object): GitResult {
    const o = r as Record<string, Object>;
    return {
      code: Number(o['code'] ?? 99),
      err: String(o['err'] ?? 'EUNKNOWN'),
      message: String(o['message'] ?? ''),
      data: String(o['data'] ?? ''),
      ok: Boolean(o['ok'] ?? false)
    };
  }

  probe(): GitResult {
    try {
      const r = this.wrap(hmGit.available());
      this.libgit2Linked = r.ok;
      if (!r.ok) {
        this.lastError = `${r.err}: ${r.message}`;
      }
      this.bump();
      return r;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.libgit2Linked = false;
      this.lastError = msg;
      this.bump();
      return { code: 3, err: 'ENOSYS', message: msg, data: '{"libgit2":false}', ok: false };
    }
  }

  async refresh(): Promise<void> {
    const rs = RemoteSession.getInstance();
    if (rs.isRemote()) {
      this.remoteSource = true;
      this.libgit2Linked = true; // treat remote git2 as available
      try {
        const st = await rs.gitStatus();
        this.repoOpen = true;
        this.branch = String(st['branch'] ?? 'HEAD');
        this.statusItems = [];
        const items = (st['items'] as Object[]) ?? [];
        for (let i = 0; i < items.length; i++) {
          const it = items[i] as Record<string, Object>;
          this.statusItems.push({
            path: String(it['path'] ?? ''),
            status: String(it['status'] ?? 'modified')
          });
        }
        this.lastError = '';
      } catch (e) {
        this.repoOpen = false;
        this.statusItems = [];
        this.lastError = e instanceof Error ? e.message : String(e);
      }
      this.bump();
      return;
    }
    this.remoteSource = false;
    this.probe();
    if (!this.libgit2Linked) {
      this.repoOpen = false;
      this.statusItems = [];
      this.branch = '';
      this.bump();
      return;
    }
    const root = WorkspaceService.getInstance().getRootPath();
    const open = this.wrap(hmGit.open(root));
    if (!open.ok) {
      this.repoOpen = false;
      this.statusItems = [];
      this.branch = '';
      this.lastError = `${open.err}: ${open.message}`;
      this.bump();
      return;
    }
    this.repoOpen = true;
    const br = this.wrap(hmGit.currentBranch());
    this.branch = br.ok ? br.message : 'HEAD';
    const st = this.wrap(hmGit.status());
    this.statusItems = [];
    if (st.ok && st.data) {
      try {
        const arr = JSON.parse(st.data) as Object[];
        for (let i = 0; i < arr.length; i++) {
          const it = arr[i] as Record<string, Object>;
          this.statusItems.push({
            path: String(it['path'] ?? ''),
            status: String(it['status'] ?? 'modified')
          });
        }
      } catch (_e) {
        // ignore parse
      }
    }
    this.lastError = '';
    this.bump();
  }


  initRepo(): GitResult {
    const root = WorkspaceService.getInstance().getRootPath();
    try {
      const r = this.wrap(hmGit.init(root));
      if (r.ok) {
        this.repoOpen = true;
        this.refresh();
      } else {
        this.lastError = `${r.err}: ${r.message}`;
        this.bump();
      }
      return r;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return { code: 99, err: 'EUNKNOWN', message: msg, data: '', ok: false };
    }
  }

  add(pathspec: string): GitResult {
    try {
      return this.wrap(hmGit.add(pathspec));
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return { code: 99, err: 'EUNKNOWN', message: msg, data: '', ok: false };
    }
  }

  commit(message: string): GitResult {
    try {
      const r = this.wrap(hmGit.commit(message, 'hm-ide', 'hm-ide@localhost'));
      this.refresh();
      return r;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return { code: 99, err: 'EUNKNOWN', message: msg, data: '', ok: false };
    }
  }

  capabilityLabel(): string {
    if (this.remoteSource) {
      return this.repoOpen ? `Git/Remote · ${this.branch || 'HEAD'}` : 'Git/Remote · 无仓库';
    }
    if (!this.libgit2Linked) {
      return 'Git（需 libgit2 预编译；远程会话走 Agent git.status）';
    }
    if (!this.repoOpen) {
      return 'Git · 无仓库';
    }
    return `Git · ${this.branch || 'HEAD'}`;
  }
}
