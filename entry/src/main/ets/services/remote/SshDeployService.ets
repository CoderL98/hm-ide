/**
 * SSH auto-deploy for hm-ide-agent (Scheme B).
 *
 * End-to-end steps (mirrors tools/ssh-deploy-agent.sh / hm-ssh-helper):
 *   1) detect remote arch via ssh
 *   2) scp/sftp upload matching agent/dist/hm-ide-agent-*-linux
 *   3) remote install to ~/.hm-ide-agent/bin/hm-ide-agent
 *   4) start agent on 127.0.0.1:port with token
 *   5) LocalForward / instruct WS URL
 *   6) hello version check; on mismatch → replace binary & restart
 *
 * On-device: tries libhm_ssh.so (ENOSYS until libssh2 linked).
 * Host path: tools/hm-ssh-helper + tools/ssh-deploy-agent.sh — documented in progress logs.
 */

export interface RemoteConnectOptions {
  host: string;
  port: number;
  user: string;
  authMode: string;
  privateKeyPath: string;
  password: string;
  remotePath: string;
  agentPort: number;
  agentToken: string;
  localWsUrl: string;
  localAgentBinary: string;
}

export interface DeployStatus {
  step: string;
  message: string;
  ok: boolean;
}

export type StatusCallback = (st: DeployStatus) => void;

export class SshDeployService {
  private static instance: SshDeployService = new SshDeployService();

  static getInstance(): SshDeployService {
    return SshDeployService.instance;
  }

  defaultOptions(): RemoteConnectOptions {
    return {
      host: '',
      port: 22,
      user: '',
      authMode: 'key',
      privateKeyPath: '',
      password: '',
      remotePath: '',
      agentPort: 17821,
      agentToken: '',
      localWsUrl: '',
      localAgentBinary: ''
    };
  }

  /**
   * Drive the full deploy pipeline with progress logs.
   * Returns ok=true only if native libssh completed; otherwise ok=false with host helper hint
   * (caller may still connect if LocalForward already active).
   */
  async deployAndForward(opts: RemoteConnectOptions, onStatus: StatusCallback): Promise<DeployStatus> {
    onStatus({ step: 'validate', message: '校验连接参数…', ok: true });
    if (!opts.host || !opts.user || !opts.remotePath) {
      return { step: 'validate', message: 'host / user / remotePath 不能为空', ok: false };
    }

    const hmSsh = this.loadHmSsh();
    if (hmSsh) {
      const avail = hmSsh.available() as Record<string, Object>;
      if (avail['ok']) {
        return this.runNativePipeline(hmSsh, opts, onStatus);
      }
      onStatus({
        step: 'native',
        message: `libhm_ssh: ${avail['code']} ${avail['message']}`,
        ok: false
      });
    } else {
      onStatus({ step: 'native', message: 'libhm_ssh.so 未注入（设备端 ENOSYS）', ok: false });
    }

    // Simulated step-by-step progress so UI shows the real host path
    onStatus({ step: 'detect', message: '① 探测远端 arch（ssh uname -m）…', ok: true });
    onStatus({
      step: 'upload',
      message: '② 上传 agent/dist/hm-ide-agent-{arch}-linux → ~/.hm-ide-agent/bin/hm-ide-agent',
      ok: true
    });
    onStatus({
      step: 'install',
      message: '③ 远端 install：chmod +x && mv .new',
      ok: true
    });
    onStatus({
      step: 'start',
      message: `④ 启动：nohup hm-ide-agent --port ${opts.agentPort}` +
        (opts.agentToken ? ' --token ***' : ''),
      ok: true
    });
    onStatus({
      step: 'forward',
      message: `⑤ LocalForward 127.0.0.1:${opts.agentPort} → 远端 127.0.0.1:${opts.agentPort}`,
      ok: true
    });
    onStatus({
      step: 'ws',
      message: `⑥ IDE 连接 ${this.wsUrl(opts)} 并 session.hello 版本校验`,
      ok: true
    });

    const cmd = this.buildHostHelperCommand(opts);
    onStatus({
      step: 'hint',
      message: `请在开发机执行（真实自动部署）：\n${cmd}`,
      ok: false
    });
    onStatus({
      step: 'hint',
      message: '或：tools/hm-ssh-helper deploy --host … --user … --remote-path …',
      ok: false
    });

    return {
      step: 'host-helper',
      message: '设备端 libssh 未就绪；主机脚本/helper 为真实自动部署路径。若已 LocalForward 可继续连 Agent。',
      ok: false
    };
  }

  async replaceBinaryAndRestart(opts: RemoteConnectOptions, onStatus: StatusCallback): Promise<DeployStatus> {
    onStatus({ step: 'replace', message: '版本不匹配 → 替换远端二进制并重启…', ok: true });
    const hmSsh = this.loadHmSsh();
    if (hmSsh) {
      try {
        const r = hmSsh.replaceAndRestart(
          opts.localAgentBinary, opts.host, opts.port, opts.user,
          opts.authMode, opts.privateKeyPath, opts.password, opts.agentPort
        ) as Record<string, Object>;
        if (r['ok']) {
          onStatus({ step: 'replace', message: 'native replace+restart ok', ok: true });
          return { step: 'replace', message: 'ok', ok: true };
        }
        onStatus({ step: 'replace', message: String(r['message'] ?? 'ENOSYS'), ok: false });
      } catch (e) {
        onStatus({
          step: 'replace',
          message: e instanceof Error ? e.message : String(e),
          ok: false
        });
      }
    }
    const forceCmd = `${this.buildHostHelperCommand(opts)} -f -n`;
    onStatus({
      step: 'hint',
      message: `主机强制升级：${forceCmd}`,
      ok: false
    });
    return {
      step: 'replace',
      message: 'hm_ssh 不可用；请用 ssh-deploy-agent.sh -f 或 hm-ssh-helper upgrade',
      ok: false
    };
  }

  buildHostHelperCommand(opts: RemoteConnectOptions): string {
    const port = opts.port > 0 ? opts.port : 22;
    const agentPort = opts.agentPort > 0 ? opts.agentPort : 17821;
    let cmd =
      `tools/ssh-deploy-agent.sh -h ${opts.host} -p ${port} -u ${opts.user} -r ${opts.remotePath} -a ${agentPort}`;
    if (opts.privateKeyPath) {
      cmd += ` -i ${opts.privateKeyPath}`;
    }
    if (opts.agentToken) {
      cmd += ` -t ${opts.agentToken}`;
    }
    if (opts.localAgentBinary) {
      cmd += ` -b ${opts.localAgentBinary}`;
    }
    return cmd;
  }

  wsUrl(opts: RemoteConnectOptions): string {
    if (opts.localWsUrl && opts.localWsUrl.length > 0) {
      return opts.localWsUrl;
    }
    const p = opts.agentPort > 0 ? opts.agentPort : 17821;
    return `ws://127.0.0.1:${p}/ws`;
  }

  private runNativePipeline(
    hmSsh: HmSshModule,
    opts: RemoteConnectOptions,
    onStatus: StatusCallback
  ): DeployStatus {
    onStatus({ step: 'detect', message: 'native: detectRemoteArch…', ok: true });
    const arch = hmSsh.detectRemoteArch(
      opts.host, opts.port, opts.user, opts.authMode, opts.privateKeyPath, opts.password
    ) as Record<string, Object>;
    if (!arch['ok']) {
      return { step: 'detect', message: String(arch['message'] ?? 'detect failed'), ok: false };
    }
    onStatus({ step: 'detect', message: `arch=${arch['arch']}`, ok: true });

    onStatus({ step: 'upload', message: 'native: uploadAgent…', ok: true });
    const up = hmSsh.uploadAgent(
      opts.localAgentBinary, opts.host, opts.port, opts.user,
      opts.authMode, opts.privateKeyPath, opts.password, opts.agentPort
    ) as Record<string, Object>;
    if (!up['ok']) {
      return { step: 'upload', message: String(up['message'] ?? 'upload failed'), ok: false };
    }

    onStatus({ step: 'start', message: 'native: installAndStart…', ok: true });
    if (hmSsh.installAndStart) {
      const st = hmSsh.installAndStart(
        opts.host, opts.port, opts.user, opts.authMode,
        opts.privateKeyPath, opts.password, opts.agentPort, opts.agentToken
      ) as Record<string, Object>;
      if (!st['ok']) {
        return { step: 'start', message: String(st['message'] ?? 'start failed'), ok: false };
      }
    }

    onStatus({ step: 'forward', message: `native: LocalForward :${opts.agentPort}`, ok: true });
    const fw = hmSsh.localForward(
      opts.host, opts.port, opts.user, opts.authMode,
      opts.privateKeyPath, opts.password, opts.agentPort
    ) as Record<string, Object>;
    if (!fw['ok']) {
      return { step: 'forward', message: String(fw['message'] ?? 'forward failed'), ok: false };
    }
    return { step: 'done', message: 'native deploy + forward ok', ok: true };
  }

  private loadHmSsh(): HmSshModule | null {
    try {
      const injected = AppStorage.get<HmSshModule>('hmSshNative');
      if (injected) {
        return injected;
      }
      return null;
    } catch (_e) {
      return null;
    }
  }
}

export interface HmSshModule {
  available: () => Object;
  detectRemoteArch: (...args: Object[]) => Object;
  uploadAgent: (...args: Object[]) => Object;
  installAndStart?: (...args: Object[]) => Object;
  localForward: (...args: Object[]) => Object;
  replaceAndRestart: (...args: Object[]) => Object;
  deployAll?: (...args: Object[]) => Object;
  hostHelperHint?: () => Object;
}
