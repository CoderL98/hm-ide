import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileNode, SearchHit } from '../models/FileNode';

const DOMAIN = 0x1DE0;
const TAG = 'Workspace';
const WORKSPACE_DIR = 'workspace/HelloWorld';

/**
 * 沙箱工作区：首次从 rawfile/sample-workspace 种子复制，之后读写 filesDir。
 */
export class WorkspaceService {
  private static instance: WorkspaceService = new WorkspaceService();
  private context: common.UIAbilityContext | null = null;
  private rootPath: string = '';
  private ready: boolean = false;

  static getInstance(): WorkspaceService {
    return WorkspaceService.instance;
  }

  getRootPath(): string {
    return this.rootPath;
  }

  isReady(): boolean {
    return this.ready;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.rootPath = `${context.filesDir}/${WORKSPACE_DIR}`;
    try {
      if (!fs.accessSync(this.rootPath)) {
        await this.seedFromRawfile();
      } else {
        const indexPath = `${this.rootPath}/entry/src/main/ets/pages/Index.ets`;
        if (!fs.accessSync(indexPath)) {
          await this.seedFromRawfile();
        }
      }
      this.ready = true;
      hilog.info(DOMAIN, TAG, 'workspace ready %{public}s', this.rootPath);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'init failed %{public}s', JSON.stringify(e));
      try {
        this.ensureDir(this.rootPath);
        this.writeTextSync(`${this.rootPath}/entry/src/main/ets/pages/Index.ets`,
          WorkspaceService.defaultIndexContent());
        this.writeTextSync(`${this.rootPath}/oh-package.json5`,
          '{\n  "name": "helloworld",\n  "version": "1.0.0"\n}\n');
        this.writeTextSync(`${this.rootPath}/entry/src/main/module.json5`,
          '{\n  "module": { "name": "entry", "type": "entry" }\n}\n');
        this.writeTextSync(`${this.rootPath}/entry/src/main/resources/base/profile/main_pages.json`,
          '{\n  "src": ["pages/Index"]\n}\n');
        this.ready = true;
      } catch (e2) {
        hilog.error(DOMAIN, TAG, 'fallback seed failed %{public}s', JSON.stringify(e2));
      }
    }
    this.bump();
  }

  /** 重新装载示例工程（欢迎页「打开示例」） */
  async reseedSample(): Promise<void> {
    await this.seedFromRawfile();
    this.ready = true;
    this.bump();
  }

  private bump(): void {
    try {
      const cur = AppStorage.get<number>('workspaceRev') ?? 0;
      AppStorage.setOrCreate('workspaceRev', cur + 1);
    } catch (_e) {
      // ignore
    }
  }

  private ensureDir(path: string): void {
    const parts = path.split('/');
    let cur = '';
    for (let i = 0; i < parts.length; i++) {
      if (!parts[i]) {
        cur += '/';
        continue;
      }
      cur = cur.endsWith('/') ? `${cur}${parts[i]}` : `${cur}/${parts[i]}`;
      try {
        if (!fs.accessSync(cur)) {
          fs.mkdirSync(cur);
        }
      } catch (_e) {
        try {
          fs.mkdirSync(cur);
        } catch (__e) {
          // exists
        }
      }
    }
  }

  private writeTextSync(path: string, content: string): void {
    const parent = path.substring(0, path.lastIndexOf('/'));
    this.ensureDir(parent);
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, content);
    fs.closeSync(file);
  }

  private static defaultIndexContent(): string {
    return `/**
 * 首页 — 鸿蒙原生应用入口
 */
@Entry
@Component
struct Index {
  @State message: string = 'Hello HarmonyOS';
  @State count: number = 0;

  build() {
    Column() {
      Text(this.message)
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
      Button('Increment')
        .onClick(() => {
          this.count += 1;
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
`;
  }

  private async seedFromRawfile(): Promise<void> {
    if (!this.context) {
      return;
    }
    const rm = this.context.resourceManager;
    const files: string[] = [
      'sample-workspace/HelloWorld/oh-package.json5',
      'sample-workspace/HelloWorld/build-profile.json5',
      'sample-workspace/HelloWorld/hvigorfile.ts',
      'sample-workspace/HelloWorld/README.md',
      'sample-workspace/HelloWorld/AppScope/app.json5',
      'sample-workspace/HelloWorld/entry/oh-package.json5',
      'sample-workspace/HelloWorld/entry/src/main/module.json5',
      'sample-workspace/HelloWorld/entry/src/main/resources/base/profile/main_pages.json',
      'sample-workspace/HelloWorld/entry/src/main/ets/pages/Index.ets'
    ];
    this.ensureDir(this.rootPath);
    for (let i = 0; i < files.length; i++) {
      const raw = files[i];
      const rel = raw.replace('sample-workspace/HelloWorld/', '');
      const dest = `${this.rootPath}/${rel}`;
      try {
        const buf = await rm.getRawFileContent(raw);
        const text = this.uint8ToString(buf);
        this.writeTextSync(dest, text);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'rawfile miss %{public}s', raw);
        if (rel.endsWith('Index.ets')) {
          this.writeTextSync(dest, WorkspaceService.defaultIndexContent());
        }
      }
    }
  }

  private uint8ToString(buf: Uint8Array): string {
    let out = '';
    const chunk = 0x8000;
    for (let i = 0; i < buf.length; i += chunk) {
      const slice = buf.subarray(i, Math.min(i + chunk, buf.length));
      out += String.fromCharCode.apply(null, Array.from(slice));
    }
    try {
      return decodeURIComponent(escape(out));
    } catch (_e) {
      return out;
    }
  }

  listTree(): FileNode[] {
    if (!this.rootPath || !fs.accessSync(this.rootPath)) {
      return [];
    }
    const root = new FileNode('root', 'HELLOWORLD', this.rootPath, true, 0);
    root.expanded = true;
    this.fillChildren(root);
    return [root];
  }

  flatten(nodes: FileNode[]): FileNode[] {
    const out: FileNode[] = [];
    const walk = (n: FileNode): void => {
      out.push(n);
      if (n.isDirectory && n.expanded) {
        for (let i = 0; i < n.children.length; i++) {
          walk(n.children[i]);
        }
      }
    };
    for (let i = 0; i < nodes.length; i++) {
      walk(nodes[i]);
    }
    return out;
  }

  private fillChildren(node: FileNode): void {
    try {
      const names = fs.listFileSync(node.path);
      names.sort((a: string, b: string) => {
        const ap = `${node.path}/${a}`;
        const bp = `${node.path}/${b}`;
        let ad = false;
        let bd = false;
        try {
          ad = fs.statSync(ap).isDirectory();
        } catch (_e) {
          ad = false;
        }
        try {
          bd = fs.statSync(bp).isDirectory();
        } catch (_e) {
          bd = false;
        }
        if (ad !== bd) {
          return ad ? -1 : 1;
        }
        return a.localeCompare(b);
      });
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        if (name === '.' || name === '..') {
          continue;
        }
        const full = `${node.path}/${name}`;
        let isDir = false;
        try {
          isDir = fs.statSync(full).isDirectory();
        } catch (_e) {
          isDir = false;
        }
        const child = new FileNode(full, name, full, isDir, node.depth + 1);
        if (isDir && child.depth < 3) {
          child.expanded = true;
          this.fillChildren(child);
        } else if (isDir) {
          child.expanded = false;
        }
        node.children.push(child);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'list fail %{public}s', node.path);
    }
  }

  /** 递归收集全部文件路径（搜索 / 命令面板） */
  listAllFiles(maxFiles: number = 500): string[] {
    const out: string[] = [];
    if (!this.rootPath) {
      return out;
    }
    this.collectFiles(this.rootPath, out, maxFiles);
    return out;
  }

  private collectFiles(dir: string, out: string[], maxFiles: number): void {
    if (out.length >= maxFiles) {
      return;
    }
    try {
      const names = fs.listFileSync(dir);
      for (let i = 0; i < names.length; i++) {
        if (out.length >= maxFiles) {
          return;
        }
        const name = names[i];
        if (name === '.' || name === '..') {
          continue;
        }
        const full = `${dir}/${name}`;
        try {
          const st = fs.statSync(full);
          if (st.isDirectory()) {
            this.collectFiles(full, out, maxFiles);
          } else {
            out.push(full);
          }
        } catch (_e) {
          // skip
        }
      }
    } catch (_e) {
      // skip
    }
  }

  /** 简单字符串搜索（大小写不敏感可选） */
  searchInFiles(query: string, maxHits: number = 80): SearchHit[] {
    const hits: SearchHit[] = [];
    const q = query.trim();
    if (!q) {
      return hits;
    }
    const qLower = q.toLowerCase();
    const files = this.listAllFiles(400);
    for (let i = 0; i < files.length; i++) {
      if (hits.length >= maxHits) {
        break;
      }
      const path = files[i];
      const name = path.substring(path.lastIndexOf('/') + 1).toLowerCase();
      // 跳过过大/二进制倾向文件
      if (name.endsWith('.png') || name.endsWith('.jpg') || name.endsWith('.ttf') ||
        name.endsWith('.woff') || name.endsWith('.bin')) {
        continue;
      }
      let content = '';
      try {
        const st = fs.statSync(path);
        if (st.size > 200000) {
          continue;
        }
        content = this.readFile(path);
      } catch (_e) {
        continue;
      }
      const lines = content.split('\n');
      for (let li = 0; li < lines.length; li++) {
        if (hits.length >= maxHits) {
          break;
        }
        const line = lines[li];
        const idx = line.toLowerCase().indexOf(qLower);
        if (idx >= 0) {
          let preview = line.trim();
          if (preview.length > 120) {
            preview = preview.substring(0, 117) + '...';
          }
          hits.push(new SearchHit(path, this.relativePath(path), li + 1, idx + 1, preview));
        }
      }
    }
    return hits;
  }

  getMtime(path: string): number {
    try {
      const st = fs.statSync(path);
      // HarmonyOS FileStat.mtime 可能是秒或毫秒；统一为毫秒近似
      const m = Number(st.mtime);
      return m < 1e12 ? m * 1000 : m;
    } catch (_e) {
      return 0;
    }
  }

  readFile(path: string): string {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(path);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      return this.uint8ToString(new Uint8Array(buf));
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'read fail %{public}s', path);
      return '';
    }
  }

  writeFile(path: string, content: string): void {
    this.writeTextSync(path, content);
    this.bump();
  }

  createFile(parentDir: string, name: string, content: string = ''): string {
    const path = `${parentDir}/${name}`;
    this.writeTextSync(path, content);
    this.bump();
    return path;
  }

  createFolder(parentDir: string, name: string): string {
    const path = `${parentDir}/${name}`;
    this.ensureDir(path);
    this.bump();
    return path;
  }

  rename(oldPath: string, newName: string): string {
    const parent = oldPath.substring(0, oldPath.lastIndexOf('/'));
    const newPath = `${parent}/${newName}`;
    try {
      fs.renameSync(oldPath, newPath);
    } catch (e) {
      try {
        const content = this.readFile(oldPath);
        this.writeTextSync(newPath, content);
        fs.unlinkSync(oldPath);
      } catch (e2) {
        hilog.error(DOMAIN, TAG, 'rename fail');
        return oldPath;
      }
    }
    this.bump();
    return newPath;
  }

  deletePath(path: string): void {
    try {
      const st = fs.statSync(path);
      if (st.isDirectory()) {
        this.deleteDirRecursive(path);
      } else {
        fs.unlinkSync(path);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'delete fail %{public}s', path);
    }
    this.bump();
  }

  private deleteDirRecursive(path: string): void {
    try {
      const names = fs.listFileSync(path);
      for (let i = 0; i < names.length; i++) {
        const full = `${path}/${names[i]}`;
        try {
          if (fs.statSync(full).isDirectory()) {
            this.deleteDirRecursive(full);
          } else {
            fs.unlinkSync(full);
          }
        } catch (_e) {
          // ignore
        }
      }
      fs.rmdirSync(path);
    } catch (_e) {
      // ignore
    }
  }

  relativePath(absPath: string): string {
    if (absPath.indexOf(this.rootPath) === 0) {
      const rel = absPath.substring(this.rootPath.length);
      return rel.startsWith('/') ? rel.substring(1) : rel;
    }
    return absPath;
  }

  detectLanguage(name: string): string {
    const lower = name.toLowerCase();
    if (lower.endsWith('.ets')) {
      return 'arkts';
    }
    if (lower.endsWith('.ts')) {
      return 'typescript';
    }
    if (lower.endsWith('.js')) {
      return 'javascript';
    }
    if (lower.endsWith('.json') || lower.endsWith('.json5')) {
      return 'json';
    }
    if (lower.endsWith('.css')) {
      return 'css';
    }
    if (lower.endsWith('.html')) {
      return 'html';
    }
    if (lower.endsWith('.md')) {
      return 'markdown';
    }
    return 'plaintext';
  }

  refreshTree(): FileNode[] {
    return this.listTree();
  }
}
