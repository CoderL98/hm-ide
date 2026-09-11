/** 工作区文件树节点 */
export class FileNode {
  id: string = '';
  name: string = '';
  path: string = '';
  isDirectory: boolean = false;
  children: FileNode[] = [];
  expanded: boolean = false;
  depth: number = 0;

  constructor(id: string, name: string, path: string, isDirectory: boolean, depth: number = 0) {
    this.id = id;
    this.name = name;
    this.path = path;
    this.isDirectory = isDirectory;
    this.depth = depth;
    this.children = [];
    this.expanded = depth < 2;
  }
}

/** 编辑器标签页 */
export class EditorTab {
  id: string = '';
  path: string = '';
  name: string = '';
  language: string = 'plaintext';
  content: string = '';
  savedContent: string = '';
  dirty: boolean = false;
  /** 磁盘 mtime（ms），用于外部变更检测 */
  diskMtime: number = 0;

  constructor(path: string, name: string, content: string, language: string) {
    this.id = path;
    this.path = path;
    this.name = name;
    this.content = content;
    this.savedContent = content;
    this.language = language;
    this.dirty = false;
    this.diskMtime = 0;
  }

  markDirty(value: string): void {
    this.content = value;
    this.dirty = this.content !== this.savedContent;
  }

  markSaved(): void {
    this.savedContent = this.content;
    this.dirty = false;
  }
}

export type BottomPanelTab = 'terminal' | 'output' | 'problems' | 'build';

export type ActivityId = 'explorer' | 'search' | 'scm' | 'extensions' | 'settings';

export class ProblemItem {
  severity: string = 'info'; // error | warning | info
  message: string = '';
  file: string = '';
  path: string = '';
  line: number = 1;
  column: number = 1;

  constructor(severity: string, message: string, file: string, line: number, path: string = '',
    column: number = 1) {
    this.severity = severity;
    this.message = message;
    this.file = file;
    this.line = line;
    this.path = path;
    this.column = column;
  }
}

/** 工作区全文搜索命中 */
export class SearchHit {
  path: string = '';
  relPath: string = '';
  line: number = 1;
  column: number = 1;
  preview: string = '';

  constructor(path: string, relPath: string, line: number, column: number, preview: string) {
    this.path = path;
    this.relPath = relPath;
    this.line = line;
    this.column = column;
    this.preview = preview;
  }
}

/** 命令面板文件条目 */
export class QuickOpenItem {
  path: string = '';
  relPath: string = '';
  name: string = '';
  score: number = 0;

  constructor(path: string, relPath: string, name: string, score: number = 0) {
    this.path = path;
    this.relPath = relPath;
    this.name = name;
    this.score = score;
  }
}
