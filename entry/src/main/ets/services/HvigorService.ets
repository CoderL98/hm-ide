/**
 * HarmonyOS 构建 / 签名配置服务。
 * 设备上通常无完整 SDK + 子进程权限；本服务检测路径、持久化配置，
 * 并在无法执行时给出明确 ENOSYS / ENOENT 错误（不假装构建成功）。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { IdeStore } from './IdeStore';
import { WorkspaceService } from './WorkspaceService';
import { RemoteSession } from './remote/RemoteSession';

export interface HvigorResult {
  ok: boolean;
  err: string;
  message: string;
  log: string;
}

export class HvigorService {
  private static instance: HvigorService = new HvigorService();
  private prefs: preferences.Preferences | null = null;

  sdkPath: string = '';
  signingConfigPath: string = '';
  lastLog: string = '';
  remoteTaskId: string = '';
  lastResult: string = '';

  static getInstance(): HvigorService {
    return HvigorService.instance;
  }

  private bump(): void {
    try {
      const cur = AppStorage.get<number>('buildRev') ?? 0;
      AppStorage.setOrCreate('buildRev', cur + 1);
    } catch (_e) {
      // ignore
    }
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    this.prefs = await preferences.getPreferences(context, 'hm_ide_build');
    this.sdkPath = String(await this.prefs.get('sdkPath', ''));
    this.signingConfigPath = String(await this.prefs.get('signingConfigPath', ''));
    this.bump();
  }

  async setSdkPath(path: string): Promise<void> {
    this.sdkPath = path.trim();
    if (this.prefs) {
      await this.prefs.put('sdkPath', this.sdkPath);
      await this.prefs.flush();
    }
    this.bump();
  }

  async setSigningConfigPath(path: string): Promise<void> {
    this.signingConfigPath = path.trim();
    if (this.prefs) {
      await this.prefs.put('signingConfigPath', this.signingConfigPath);
      await this.prefs.flush();
    }
    this.bump();
  }

  private pathExists(p: string): boolean {
    if (!p) {
      return false;
    }
    try {
      fs.statSync(p);
      return true;
    } catch (_e) {
      return false;
    }
  }

  detectSdk(): HvigorResult {
    const candidates: string[] = [];
    if (this.sdkPath) {
      candidates.push(this.sdkPath);
    }
    // Common DevEco / OHOS host paths (may exist on 2in1 with SDK installed)
    candidates.push('/Users/Shared/Huawei/Sdk');
    candidates.push('/opt/Huawei/Sdk');
    candidates.push('/home/user/Huawei/Sdk');
    candidates.push(this.sdkPath);

    for (let i = 0; i < candidates.length; i++) {
      const c = candidates[i];
      if (!c) {
        continue;
      }
      if (this.pathExists(c)) {
        this.sdkPath = c;
        this.lastResult = `检测到 SDK: ${c}`;
        this.bump();
        return { ok: true, err: 'OK', message: this.lastResult, log: c };
      }
    }
    this.lastResult = '未找到 HarmonyOS SDK。请在构建设置中填写 sdkPath（DevEco 本机 SDK 根目录）。';
    this.bump();
    return {
      ok: false,
      err: 'ENOENT',
      message: this.lastResult,
      log: ''
    };
  }

  /**
   * 「构建 entry」— 设备端诚实降级。
   * 完整 hvigor assemble 需要宿主 NDK/SDK 与子进程；普通应用沙箱通常不可用。
   */
  assembleEntry(): HvigorResult {
    const rs = RemoteSession.getInstance();
    if (rs.isRemote()) {
      return this.assembleEntryRemote(rs);
    }
    const lines: string[] = [];
    lines.push('[hvigor] assembleHap / entry');
    const det = this.detectSdk();
    if (!det.ok) {
      lines.push(`[error] ${det.err}: ${det.message}`);
      this.lastLog = lines.join('\n');
      IdeStore.getInstance().appendOutput(this.lastLog);
      this.bump();
      return { ok: false, err: det.err, message: det.message, log: this.lastLog };
    }
    lines.push(`[info] SDK = ${this.sdkPath}`);
    const root = WorkspaceService.getInstance().getRootPath();
    lines.push(`[info] project = ${root}`);
    const hvigorw = `${this.sdkPath}/hvigor/bin/hvigorw`;
    const altHvigor = `${root}/hvigorw`;
    const hasWrapper = this.pathExists(hvigorw) || this.pathExists(altHvigor);
    if (!hasWrapper) {
      lines.push('[warn] 未找到 hvigorw；设备端通常无完整构建工具链。');
    }
    lines.push('[ENOSYS] 本应用为普通 Stage 应用：无法在设备沙箱内可靠 spawn hvigor。');
    lines.push('请在 DevEco Studio 主机执行：');
    lines.push('  hvigorw assembleHap -p module=entry');
    lines.push('或配置外部 CI。签名配置路径仅作记录：' +
      (this.signingConfigPath || '（未设置）'));
    this.lastLog = lines.join('\n');
    this.lastResult = 'ENOSYS: 设备端无法执行 hvigor（请用 DevEco 主机构建）';
    IdeStore.getInstance().appendOutput(this.lastLog);
    IdeStore.getInstance().setBottomTab('output');
    this.bump();
    return { ok: false, err: 'ENOSYS', message: this.lastResult, log: this.lastLog };
  }

  signingHint(): string {
    if (!this.signingConfigPath) {
      return '未配置签名材料路径。DevEco：File → Project Structure → Signing Configs。';
    }
    if (!this.pathExists(this.signingConfigPath)) {
      return `签名路径不存在: ${this.signingConfigPath}`;
    }
    return `签名配置: ${this.signingConfigPath}`;
  }
}
