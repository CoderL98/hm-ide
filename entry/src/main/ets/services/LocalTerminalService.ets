import { fileIo as fs } from '@kit.CoreFileKit';
import { WorkspaceService } from './WorkspaceService';
import { IdeStore } from './IdeStore';
import { NativePtyService } from './NativePtyService';
import { RemoteSession } from './remote/RemoteSession';

/**
 * 本地终端能力（诚实标注）
 * - native-pty: Native C++ NAPI（libhm_pty.so）真实 PTY；设备上可能被 SELinux 拒绝 → 自动回退
 * - sandbox-shell: 应用内建沙箱命令（fileIo），行缓冲交互；非 OS PTY（回退）
 * - process-pipe: 仅文档/预留（系统 API）
 * - none: 未启动
 */
export type TerminalCapability = 'none' | 'native-pty' | 'remote-pty' | 'sandbox-shell' | 'process-pipe';

/**
 * 本地交互终端：优先原生 PTY，失败则沙箱壳。
 * xterm.js 前端不变；Native 路径下按键直写 master，定时 drain 输出。
 */
export class LocalTerminalService {
  private static instance: LocalTerminalService = new LocalTerminalService();

  capability: TerminalCapability = 'none';
  sessionActive: boolean = false;
  cwd: string = '';
  cols: number = 80;
  rows: number = 24;
  private lineBuf: string = '';
  private busy: boolean = false;
  private nativeSessionId: number = -1;
  private drainTimer: number = -1;
  private lastNativeError: string = '';

  static getInstance(): LocalTerminalService {
    return LocalTerminalService.instance;
  }

  private bump(): void {
    try {
      const cur = AppStorage.get<number>('termSessionRev') ?? 0;
      AppStorage.setOrCreate('termSessionRev', cur + 1);
    } catch (_e) {
      // ignore
    }
  }

  capabilityLabel(): string {
    if (this.capability === 'remote-pty') {
      return '远程 Agent PTY';
    }
    if (this.capability === 'native-pty') {
      return '原生 PTY';
    }
    if (this.capability === 'process-pipe') {
      return '管道 shell（近似 PTY）';
    }
    if (this.capability === 'sandbox-shell') {
      return '沙箱交互壳（回退）';
    }
    return '终端未启动';
  }

  statusBarLabel(): string {
    if (!this.sessionActive) {
      return '终端';
    }
    if (this.capability === 'remote-pty') {
      return '远程 PTY';
    }
    if (this.capability === 'native-pty') {
      return '原生 PTY';
    }
    return '沙箱壳';
  }

  lastError(): string {
    return this.lastNativeError;
  }

  /** When remote session becomes active, restart terminal on agent PTY. */
  switchToRemoteIfNeeded(): void {
    if (!RemoteSession.getInstance().isRemote()) {
      return;
    }
    if (this.capability === 'remote-pty' && this.sessionActive) {
      return;
    }
    this.stopSession();
    this.startSession();
  }

  startSession(): void {
    if (this.sessionActive) {
      return;
    }
    this.cwd = WorkspaceService.getInstance().getRootPath();
    this.lineBuf = '';
    this.busy = false;
    this.nativeSessionId = -1;
    this.lastNativeError = '';
    this.stopDrainTimer();

    // 0) Prefer remote agent PTY when Scheme B session active
    if (this.tryStartRemotePty()) {
      return;
    }

    // 1) Prefer Native C++ PTY
    if (this.tryStartNativePty()) {
      this.capability = 'native-pty';
      this.sessionActive = true;
      this.notifyMode('local');
      this.notifyClear();
      this.writeNativeBanner();
      this.startDrainTimer();
      IdeStore.getInstance().appendOutput(`[Terminal] 已启动 · ${this.capabilityLabel()} (#${this.nativeSessionId})`);
      IdeStore.getInstance().terminalLines = [
        '# 本地终端：原生 PTY（libhm_pty.so）',
        `# cwd: ${this.cwd}`,
        '# 详见 README「终端与 PTY」'
      ];
      this.bump();
      return;
    }

    // 2) Fallback: sandbox interactive shell
    this.capability = 'sandbox-shell';
    this.sessionActive = true;
    this.notifyMode('local');
    this.notifyClear();
    this.writeBanner();
    this.writePrompt();
    IdeStore.getInstance().appendOutput(
      `[Terminal] 已启动 · ${this.capabilityLabel()}` +
      (this.lastNativeError ? `（原生失败: ${this.lastNativeError}）` : ''));
    IdeStore.getInstance().terminalLines = [
      '# 本地终端：沙箱交互壳（回退 · 非真实 PTY）',
      `# cwd: ${this.cwd}`,
      this.lastNativeError ? `# 原生 PTY: ${this.lastNativeError}` : '# 原生 PTY 不可用',
      '# 详见 README「终端与 PTY」'
    ];
    this.bump();
  }

  private remotePollTimer: number = -1;

  private tryStartRemotePty(): boolean {
    const rs = RemoteSession.getInstance();
    if (!rs.isRemote()) {
      return false;
    }
    this.capability = 'remote-pty';
    this.sessionActive = true;
    this.cwd = (rs.options != null ? rs.options.remotePath : this.cwd);
    this.notifyMode('remote');
    this.notifyClear();
    this.notifyData('\x1b[36m[远程 PTY]\x1b[0m hm-ide-agent\r\n');
    this.notifyData(`# cwd: ${this.cwd}\r\n`);
    rs.openPty(this.cols, this.rows, this.cwd).then((id: string) => {
      IdeStore.getInstance().appendOutput(`[Terminal] 远程 PTY 已打开 ${id}`);
      this.startRemotePtyPoll();
    }).catch((e: Error) => {
      this.notifyData(`\x1b[31m远程 PTY 打开失败: ${e.message}\x1b[0m\r\n`);
      this.lastNativeError = e.message;
    });
    IdeStore.getInstance().terminalLines = [
      '# 远程终端：hm-ide-agent PTY',
      `# cwd: ${this.cwd}`
    ];
    this.bump();
    return true;
  }

  private startRemotePtyPoll(): void {
    if (this.remotePollTimer >= 0) {
      clearInterval(this.remotePollTimer);
    }
    let lastRev = AppStorage.get<number>('remotePtyRev') ?? 0;
    this.remotePollTimer = setInterval(() => {
      const rev = AppStorage.get<number>('remotePtyRev') ?? 0;
      if (rev !== lastRev) {
        lastRev = rev;
        const chunk = AppStorage.get<string>('remotePtyChunk') ?? '';
        if (chunk) {
          this.notifyData(chunk);
        }
      }
    }, 30) as number;
  }

  private stopRemotePtyPoll(): void {
    if (this.remotePollTimer >= 0) {
      clearInterval(this.remotePollTimer);
      this.remotePollTimer = -1;
    }
  }

    private tryStartNativePty(): boolean {
    try {
      const npt = NativePtyService.getInstance();
      const av = npt.available();
      if (!av.ok) {
        this.lastNativeError = `${av.err}: ${av.message}`;
        return false;
      }
      const st = npt.start(this.cols, this.rows, this.cwd, '');
      if (!st.ok || st.sessionId < 0) {
        this.lastNativeError = `${st.err}: ${st.message}`;
        return false;
      }
      this.nativeSessionId = st.sessionId;
      this.lastNativeError = '';
      return true;
    } catch (e) {
      this.lastNativeError = e instanceof Error ? e.message : String(e);
      return false;
    }
  }

  private startDrainTimer(): void {
    this.stopDrainTimer();
    this.drainTimer = setInterval(() => {
      this.drainNative();
    }, 50) as number;
  }

  private stopDrainTimer(): void {
    if (this.drainTimer >= 0) {
      clearInterval(this.drainTimer);
      this.drainTimer = -1;
    }
  }

  private drainNative(): void {
    if (this.capability !== 'native-pty' || this.nativeSessionId < 0) {
      return;
    }
    const r = NativePtyService.getInstance().drain(this.nativeSessionId);
    if (r.ok && r.data && r.data.length > 0) {
      this.notifyData(r.data);
    }
    if (r.message === 'exited') {
      this.notifyData('\r\n\x1b[33m[原生 PTY] 子进程已退出\x1b[0m\r\n');
      this.stopDrainTimer();
    }
  }

  stopSession(): void {
    if (!this.sessionActive) {
      return;
    }
    this.stopDrainTimer();
    this.stopRemotePtyPoll();
    if (this.capability === 'remote-pty') {
      try {
        RemoteSession.getInstance().closePty();
      } catch (_e) {
        // ignore
      }
    }
    if (this.capability === 'native-pty' && this.nativeSessionId >= 0) {
      try {
        NativePtyService.getInstance().kill(this.nativeSessionId);
      } catch (_e) {
        // ignore
      }
      this.nativeSessionId = -1;
    }
    this.sessionActive = false;
    this.busy = false;
    this.lineBuf = '';
    this.capability = 'none';
    this.notifyData('\r\n\x1b[33m[终端] 会话已结束\x1b[0m\r\n');
    IdeStore.getInstance().appendOutput('[Terminal] 会话已结束');
    this.bump();
  }

  ensureSession(): void {
    if (!this.sessionActive) {
      this.startSession();
    }
  }

  /** WebView 就绪后重放横幅，避免 AppStorage 写入早于 xterm */
  reattachFrontend(): void {
    if (!this.sessionActive) {
      this.startSession();
      return;
    }
    this.notifyMode('local');
    this.notifyClear();
    if (this.capability === 'native-pty') {
      this.writeNativeBanner();
      // 不重写 prompt：真实 shell 自己画
    } else {
      this.writeBanner();
      this.writePrompt();
    }
  }

  resize(cols: number, rows: number): void {
    this.cols = cols > 0 ? cols : this.cols;
    this.rows = rows > 0 ? rows : this.rows;
    if (this.capability === 'remote-pty') {
      RemoteSession.getInstance().resizePty(this.cols, this.rows).catch(() => {});
      return;
    }
    if (this.capability === 'native-pty' && this.nativeSessionId >= 0) {
      NativePtyService.getInstance().resize(this.nativeSessionId, this.cols, this.rows);
    }
  }

  onInput(data: string): void {
    if (this.capability === 'remote-pty') {
      RemoteSession.getInstance().writePty(data).catch(() => {});
      return;
    }
    if (!this.sessionActive) {
      this.ensureSession();
    }
    if (!data) {
      return;
    }
    // Native PTY: bytes go straight to master fd
    if (this.capability === 'native-pty' && this.nativeSessionId >= 0) {
      NativePtyService.getInstance().write(this.nativeSessionId, data);
      return;
    }
    if (data === '\u0003') {
      this.handleInterrupt();
      return;
    }
    if (data === '\u000c') {
      this.notifyClear();
      this.writePrompt();
      return;
    }
    if (data === '\u007f' || data === '\b') {
      if (this.lineBuf.length > 0) {
        this.lineBuf = this.lineBuf.substring(0, this.lineBuf.length - 1);
        this.notifyData('\b \b');
      }
      return;
    }
    if (data === '\r' || data === '\n') {
      this.notifyData('\r\n');
      const line = this.lineBuf;
      this.lineBuf = '';
      this.executeLine(line.trim());
      return;
    }
    if (data.charCodeAt(0) < 32 && data.length === 1) {
      return;
    }
    if (data.indexOf('\r') >= 0 || data.indexOf('\n') >= 0) {
      const parts = splitLines(data);
      for (let i = 0; i < parts.length; i++) {
        if (i > 0) {
          this.notifyData('\r\n');
          const line = this.lineBuf;
          this.lineBuf = '';
          this.executeLine(line.trim());
        }
        if (parts[i]) {
          this.lineBuf += parts[i];
          this.notifyData(parts[i]);
        }
      }
      return;
    }
    this.lineBuf += data;
    this.notifyData(data);
  }

  private handleInterrupt(): void {
    this.busy = false;
    this.lineBuf = '';
    this.notifyData('^C\r\n');
    this.writePrompt();
  }

  private writeNativeBanner(): void {
    const errHint = this.lastNativeError ? ` · 上次错误 ${this.lastNativeError}` : '';
    this.notifyData([
      '\x1b[1m鸿蒙原生IDE · 原生 PTY\x1b[0m',
      `\x1b[90m能力：${this.capabilityLabel()} · session #${this.nativeSessionId}${errHint}\x1b[0m`,
      '\x1b[90m后端：libhm_pty.so（forkpty/posix_openpt + /bin/sh）\x1b[0m',
      `\x1b[90mcwd: ${this.cwd}\x1b[0m`,
      '\x1b[90m按键直达 PTY；窗口缩放会 TIOCSWINSZ。若设备 SELinux 拒绝 ptmx 将自动回退沙箱壳。\x1b[0m',
      ''
    ].join('\r\n'));
  }

  private writeBanner(): void {
    const nativeHint = this.lastNativeError
      ? `\x1b[90m原生 PTY 不可用：${this.lastNativeError}\x1b[0m`
      : '\x1b[90m原生 PTY 未就绪，使用沙箱交互壳（回退）。\x1b[0m';
    this.notifyData([
      '\x1b[1m鸿蒙原生IDE · 本地终端\x1b[0m',
      `\x1b[90m能力：${this.capabilityLabel()}\x1b[0m`,
      nativeHint,
      '\x1b[90m内建：help cd pwd ls cat echo mkdir touch rm clear whoami exit\x1b[0m',
      `\x1b[90mcwd: ${this.cwd}\x1b[0m`,
      ''
    ].join('\r\n'));
  }

  private writePrompt(): void {
    this.notifyData(`\x1b[32mhm\x1b[0m:\x1b[34m${this.shortCwd()}\x1b[0m$ `);
  }

  private shortCwd(): string {
    const root = WorkspaceService.getInstance().getRootPath();
    if (this.cwd === root) {
      return '~';
    }
    if (this.cwd.indexOf(root + '/') === 0) {
      return '~/' + this.cwd.substring(root.length + 1);
    }
    const parts = this.cwd.split('/');
    return parts[parts.length - 1] || this.cwd;
  }

  private executeLine(line: string): void {
    if (!line) {
      this.writePrompt();
      return;
    }
    this.busy = true;
    try {
      const handled = this.runBuiltin(line);
      if (!handled) {
        this.notifyData(`\x1b[31m命令未找到: ${line}\x1b[0m\r\n`);
        this.notifyData('\x1b[90m输入 help 查看内建命令。OS 级 shell/PTY 见 README（已推迟 / 需系统能力）。\x1b[0m\r\n');
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.notifyData(`\x1b[31m错误: ${msg}\x1b[0m\r\n`);
    }
    this.busy = false;
    if (this.sessionActive) {
      this.writePrompt();
    }
  }

  private runBuiltin(line: string): boolean {
    const parts = this.splitArgs(line);
    if (parts.length === 0) {
      return true;
    }
    const cmd = parts[0];
    const args = parts.slice(1);

    if (cmd === 'help') {
      this.notifyData([
        '内建命令（工作区沙箱 fileIo · 非 PTY）：',
        '  help / pwd / cd [dir] / ls [dir] / cat <file>',
        '  echo <text> / mkdir <dir> / touch <file> / rm <path>',
        '  clear / whoami / exit',
        '按键：Enter 执行 · Backspace 删字 · Ctrl+C 取消行 · Ctrl+L 清屏',
        ''
      ].join('\r\n'));
      return true;
    }
    if (cmd === 'clear') {
      this.notifyClear();
      return true;
    }
    if (cmd === 'pwd') {
      this.notifyData(this.cwd + '\r\n');
      return true;
    }
    if (cmd === 'whoami') {
      this.notifyData('hm-ide\r\n');
      return true;
    }
    if (cmd === 'echo') {
      this.notifyData(args.join(' ') + '\r\n');
      return true;
    }
    if (cmd === 'cd') {
      this.cmdCd(args[0] ?? '');
      return true;
    }
    if (cmd === 'ls') {
      this.cmdLs(args[0] ?? '.');
      return true;
    }
    if (cmd === 'cat') {
      if (!args[0]) {
        this.notifyData('用法: cat <file>\r\n');
      } else {
        this.cmdCat(args[0]);
      }
      return true;
    }
    if (cmd === 'mkdir') {
      if (!args[0]) {
        this.notifyData('用法: mkdir <dir>\r\n');
      } else {
        this.cmdMkdir(args[0]);
      }
      return true;
    }
    if (cmd === 'touch') {
      if (!args[0]) {
        this.notifyData('用法: touch <file>\r\n');
      } else {
        this.cmdTouch(args[0]);
      }
      return true;
    }
    if (cmd === 'rm') {
      if (!args[0]) {
        this.notifyData('用法: rm <path>\r\n');
      } else {
        this.cmdRm(args[0]);
      }
      return true;
    }
    if (cmd === 'exit') {
      this.stopSession();
      return true;
    }
    return false;
  }

  private resolvePath(p: string): string {
    if (!p || p === '.') {
      return this.cwd;
    }
    if (p === '~') {
      return WorkspaceService.getInstance().getRootPath();
    }
    if (p.indexOf('~/') === 0) {
      return `${WorkspaceService.getInstance().getRootPath()}/${p.substring(2)}`;
    }
    if (p.charAt(0) === '/') {
      return p;
    }
    return normalizeSlashes(`${this.cwd}/${p}`);
  }

  private assertInSandbox(abs: string): boolean {
    const root = WorkspaceService.getInstance().getRootPath();
    const norm = normalizeSlashes(abs);
    if (norm !== root && norm.indexOf(root + '/') !== 0) {
      this.notifyData('\x1b[31m拒绝：路径超出工作区沙箱\x1b[0m\r\n');
      return false;
    }
    return true;
  }

  private cmdCd(arg: string): void {
    const target = this.resolvePath(arg || '~');
    if (!this.assertInSandbox(target)) {
      return;
    }
    try {
      const st = fs.statSync(target);
      if (!st.isDirectory()) {
        this.notifyData(`\x1b[31m不是目录: ${arg}\x1b[0m\r\n`);
        return;
      }
      this.cwd = target;
    } catch (_e) {
      this.notifyData(`\x1b[31m目录不存在: ${arg}\x1b[0m\r\n`);
    }
  }

  private cmdLs(arg: string): void {
    const target = this.resolvePath(arg);
    if (!this.assertInSandbox(target)) {
      return;
    }
    try {
      const names = fs.listFileSync(target);
      names.sort();
      const out: string[] = [];
      for (let i = 0; i < names.length; i++) {
        let mark = '';
        try {
          if (fs.statSync(`${target}/${names[i]}`).isDirectory()) {
            mark = '/';
          }
        } catch (_e) {
          // ignore
        }
        out.push(names[i] + mark);
      }
      this.notifyData((out.length ? out.join('  ') : '') + '\r\n');
    } catch (_e) {
      this.notifyData(`\x1b[31mls 失败: ${arg}\x1b[0m\r\n`);
    }
  }

  private cmdCat(arg: string): void {
    const target = this.resolvePath(arg);
    if (!this.assertInSandbox(target)) {
      return;
    }
    try {
      const text = WorkspaceService.getInstance().readFile(target);
      const normalized = toCrlf(text);
      this.notifyData(normalized);
      if (!normalized.endsWith('\r\n')) {
        this.notifyData('\r\n');
      }
    } catch (_e) {
      this.notifyData(`\x1b[31mcat 失败: ${arg}\x1b[0m\r\n`);
    }
  }

  private cmdMkdir(arg: string): void {
    const target = this.resolvePath(arg);
    if (!this.assertInSandbox(target)) {
      return;
    }
    try {
      fs.mkdirSync(target);
      IdeStore.getInstance().refreshTree();
    } catch (_e) {
      this.notifyData(`\x1b[31mmkdir 失败: ${arg}\x1b[0m\r\n`);
    }
  }

  private cmdTouch(arg: string): void {
    const target = this.resolvePath(arg);
    if (!this.assertInSandbox(target)) {
      return;
    }
    try {
      const f = fs.openSync(target, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.closeSync(f);
      IdeStore.getInstance().refreshTree();
    } catch (_e) {
      this.notifyData(`\x1b[31mtouch 失败: ${arg}\x1b[0m\r\n`);
    }
  }

  private cmdRm(arg: string): void {
    const target = this.resolvePath(arg);
    if (!this.assertInSandbox(target)) {
      return;
    }
    try {
      WorkspaceService.getInstance().deletePath(target);
      IdeStore.getInstance().refreshTree();
    } catch (_e) {
      this.notifyData(`\x1b[31mrm 失败: ${arg}\x1b[0m\r\n`);
    }
  }

  private splitArgs(line: string): string[] {
    const out: string[] = [];
    let cur = '';
    let quote = '';
    for (let i = 0; i < line.length; i++) {
      const ch = line.charAt(i);
      if (quote) {
        if (ch === quote) {
          quote = '';
        } else {
          cur += ch;
        }
        continue;
      }
      if (ch === '"' || ch === '\'') {
        quote = ch;
        continue;
      }
      if (ch === ' ' || ch === '\t') {
        if (cur) {
          out.push(cur);
          cur = '';
        }
        continue;
      }
      cur += ch;
    }
    if (cur) {
      out.push(cur);
    }
    return out;
  }

  private notifyMode(mode: string): void {
    try {
      AppStorage.setOrCreate('termMode', mode);
      const cur = AppStorage.get<number>('termCmdRev') ?? 0;
      AppStorage.setOrCreate('termPendingCmd', `mode:${mode}`);
      AppStorage.setOrCreate('termCmdRev', cur + 1);
    } catch (_e) {
      // ignore
    }
  }

  private notifyData(data: string): void {
    try {
      AppStorage.setOrCreate('termPendingData', data);
      const cur = AppStorage.get<number>('termDataRev') ?? 0;
      AppStorage.setOrCreate('termDataRev', cur + 1);
    } catch (_e) {
      // ignore
    }
  }

  private notifyClear(): void {
    try {
      const cur = AppStorage.get<number>('termCmdRev') ?? 0;
      AppStorage.setOrCreate('termPendingCmd', 'clear');
      AppStorage.setOrCreate('termCmdRev', cur + 1);
    } catch (_e) {
      // ignore
    }
  }
}

function normalizeSlashes(s: string): string {
  let out = '';
  let prevSlash = false;
  for (let i = 0; i < s.length; i++) {
    const ch = s.charAt(i);
    if (ch === '/') {
      if (!prevSlash) {
        out += ch;
      }
      prevSlash = true;
    } else {
      out += ch;
      prevSlash = false;
    }
  }
  return out;
}

function toCrlf(text: string): string {
  let out = '';
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i);
    if (ch === '\r') {
      if (i + 1 < text.length && text.charAt(i + 1) === '\n') {
        out += '\r\n';
        i++;
      } else {
        out += '\r\n';
      }
    } else if (ch === '\n') {
      out += '\r\n';
    } else {
      out += ch;
    }
  }
  return out;
}

function splitLines(data: string): string[] {
  const parts: string[] = [];
  let cur = '';
  for (let i = 0; i < data.length; i++) {
    const ch = data.charAt(i);
    if (ch === '\r') {
      parts.push(cur);
      cur = '';
      if (i + 1 < data.length && data.charAt(i + 1) === '\n') {
        i++;
      }
    } else if (ch === '\n') {
      parts.push(cur);
      cur = '';
    } else {
      cur += ch;
    }
  }
  parts.push(cur);
  return parts;
}
