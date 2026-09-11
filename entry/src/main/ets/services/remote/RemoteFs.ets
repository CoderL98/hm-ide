import { FileNode } from '../../models/FileNode';
import { AgentClient } from './AgentClient';

export interface FsListEntry {
  name: string;
  path: string;
  is_dir: boolean;
  size: number;
  mtime_ms: number;
}

/**
 * Remote filesystem facade over AgentClient JSON-RPC.
 */
export class RemoteFs {
  private client: AgentClient;
  rootPath: string = '';

  constructor(client: AgentClient) {
    this.client = client;
  }

  setRoot(path: string): void {
    this.rootPath = path;
  }

  async list(path: string): Promise<FsListEntry[]> {
    const res = await this.client.request('fs.list', { path }) as Record<string, Object>;
    const entries = (res['entries'] as FsListEntry[]) ?? [];
    return entries;
  }

  async read(path: string): Promise<string> {
    const res = await this.client.request('fs.read', { path, encoding: 'utf8' }) as Record<string, Object>;
    return String(res['data'] ?? '');
  }

  async write(path: string, data: string): Promise<void> {
    await this.client.request('fs.write', { path, data, encoding: 'utf8' });
  }

  async mkdir(path: string): Promise<void> {
    await this.client.request('fs.mkdir', { path });
  }

  async remove(path: string, recursive: boolean = true): Promise<void> {
    await this.client.request('fs.remove', { path, recursive });
  }

  async rename(from: string, to: string): Promise<void> {
    await this.client.request('fs.rename', { from, to });
  }

  async stat(path: string): Promise<Record<string, Object>> {
    return await this.client.request('fs.stat', { path }) as Record<string, Object>;
  }

  async getMtime(path: string): Promise<number> {
    try {
      const s = await this.stat(path);
      return Number(s['mtime_ms'] ?? 0);
    } catch (_e) {
      return 0;
    }
  }

  /** Build a shallow FileNode tree (depth-limited lazy expand). */
  async buildTree(root: string, depth: number = 2): Promise<FileNode[]> {
    const entries = await this.list(root);
    const nodes: FileNode[] = [];
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i];
      if (e.name === '.' || e.name === '..') {
        continue;
      }
      const node = new FileNode(e.path, e.name, e.path, e.is_dir, 0);
      if (e.is_dir && depth > 1) {
        try {
          node.children = await this.buildTreeChildren(e.path, 1, depth - 1);
          node.expanded = true;
        } catch (_e) {
          node.children = [];
        }
      }
      nodes.push(node);
    }
    return nodes;
  }

  private async buildTreeChildren(path: string, depth: number, maxDepth: number): Promise<FileNode[]> {
    const entries = await this.list(path);
    const nodes: FileNode[] = [];
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i];
      if (e.name === '.' || e.name === '..') {
        continue;
      }
      const node = new FileNode(e.path, e.name, e.path, e.is_dir, depth);
      if (e.is_dir && depth < maxDepth) {
        try {
          node.children = await this.buildTreeChildren(e.path, depth + 1, maxDepth);
          node.expanded = depth < 2;
        } catch (_e) {
          node.children = [];
        }
      }
      nodes.push(node);
    }
    return nodes;
  }

  async search(query: string, maxHits: number = 80): Promise<Object[]> {
    const res = await this.client.request('fs.search', {
      path: this.rootPath,
      query,
      maxHits,
      caseInsensitive: true
    }) as Record<string, Object>;
    return (res['hits'] as Object[]) ?? [];
  }

  async watch(path: string, recursive: boolean = true): Promise<string> {
    const res = await this.client.request('fs.watch', { path, recursive }) as Record<string, Object>;
    return String(res['watchId'] ?? '');
  }

  async unwatch(watchId: string): Promise<void> {
    await this.client.request('fs.unwatch', { watchId });
  }

  detectLanguage(name: string): string {
    const lower = name.toLowerCase();
    if (lower.endsWith('.ets') || lower.endsWith('.ts')) {
      return 'arkts';
    }
    if (lower.endsWith('.json5') || lower.endsWith('.json')) {
      return 'json';
    }
    if (lower.endsWith('.md')) {
      return 'markdown';
    }
    if (lower.endsWith('.css')) {
      return 'css';
    }
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return 'html';
    }
    if (lower.endsWith('.rs')) {
      return 'rust';
    }
    if (lower.endsWith('.py')) {
      return 'python';
    }
    if (lower.endsWith('.c') || lower.endsWith('.h')) {
      return 'c';
    }
    if (lower.endsWith('.cpp') || lower.endsWith('.cc') || lower.endsWith('.hpp')) {
      return 'cpp';
    }
    if (lower.endsWith('.sh')) {
      return 'shell';
    }
    return 'plaintext';
  }
}
