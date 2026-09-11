import { IdeTheme } from '../../theme/IdeColors';
import { RemoteSession } from '../../services/remote/RemoteSession';
import { SshDeployService, RemoteConnectOptions } from '../../services/remote/SshDeployService';

@CustomDialog
export struct RemoteConnectDialog {
  controller!: CustomDialogController;
  @State host: string = '';
  @State sshPort: string = '22';
  @State user: string = '';
  @State authMode: string = 'key';
  @State privateKeyPath: string = '';
  @State password: string = '';
  @State remotePath: string = '';
  @State agentPort: string = '17821';
  @State agentToken: string = '';
  @State localWsUrl: string = '';
  @State busy: boolean = false;
  @State statusMsg: string = '';
  onConnected?: () => void;

  private buildOpts(): RemoteConnectOptions {
    const base = SshDeployService.getInstance().defaultOptions();
    base.host = this.host.trim();
    base.port = Number(this.sshPort) || 22;
    base.user = this.user.trim();
    base.authMode = this.authMode;
    base.privateKeyPath = this.privateKeyPath.trim();
    base.password = this.password;
    base.remotePath = this.remotePath.trim();
    base.agentPort = Number(this.agentPort) || 17821;
    base.agentToken = this.agentToken;
    base.localWsUrl = this.localWsUrl.trim();
    return base;
  }

  build() {
    Column({ space: 10 }) {
      Text('打开远程文件夹')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(IdeTheme.palette().foreground)
        .width('100%')

      Text('经 SSH 部署/转发 hm-ide-agent 后连接。设备端 libssh 未就绪时可先在主机跑 tools/ssh-deploy-agent.sh，再填 Local WS。')
        .fontSize(11)
        .fontColor(IdeTheme.palette().mutedForeground)
        .width('100%')

      this.Field('主机', this.host, (v: string) => { this.host = v; }, '192.168.1.10')
      this.Field('SSH 端口', this.sshPort, (v: string) => { this.sshPort = v; }, '22')
      this.Field('用户', this.user, (v: string) => { this.user = v; }, 'dev')
      Row({ space: 8 }) {
        Text('密钥')
          .fontSize(12)
          .fontColor(this.authMode === 'key' ? IdeTheme.palette().primaryForeground : IdeTheme.palette().foreground)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(4)
          .backgroundColor(this.authMode === 'key' ? IdeTheme.palette().primary : IdeTheme.palette().muted)
          .onClick(() => { this.authMode = 'key'; })
        Text('密码')
          .fontSize(12)
          .fontColor(this.authMode === 'password' ? IdeTheme.palette().primaryForeground : IdeTheme.palette().foreground)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(4)
          .backgroundColor(this.authMode === 'password' ? IdeTheme.palette().primary : IdeTheme.palette().muted)
          .onClick(() => { this.authMode = 'password'; })
      }
      .width('100%')

      if (this.authMode === 'key') {
        this.Field('私钥路径', this.privateKeyPath, (v: string) => { this.privateKeyPath = v; }, '~/.ssh/id_ed25519')
      } else {
        this.Field('密码', this.password, (v: string) => { this.password = v; }, '')
      }

      this.Field('远程路径', this.remotePath, (v: string) => { this.remotePath = v; }, '/home/dev/project')
      this.Field('Agent 端口', this.agentPort, (v: string) => { this.agentPort = v; }, '17821')
      this.Field('Agent Token（可选）', this.agentToken, (v: string) => { this.agentToken = v; }, '')
      this.Field('Local WS（可选）', this.localWsUrl, (v: string) => { this.localWsUrl = v; }, 'ws://127.0.0.1:17821/ws')

      if (this.statusMsg) {
        Text(this.statusMsg)
          .fontSize(11)
          .fontColor(IdeTheme.palette().mutedForeground)
          .width('100%')
      }

      Row({ space: 10 }) {
        Text('取消')
          .fontSize(13)
          .fontColor(IdeTheme.palette().foreground)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(6)
          .backgroundColor(IdeTheme.palette().muted)
          .onClick(() => this.controller.close())

        Text(this.busy ? '连接中…' : '连接')
          .fontSize(13)
          .fontColor(IdeTheme.palette().primaryForeground)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(6)
          .backgroundColor(IdeTheme.palette().primary)
          .opacity(this.busy ? 0.6 : 1)
          .onClick(async () => {
            if (this.busy) {
              return;
            }
            this.busy = true;
            this.statusMsg = '连接中…';
            const ok = await RemoteSession.getInstance().connect(this.buildOpts());
            this.busy = false;
            if (ok) {
              this.statusMsg = '已连接';
              if (this.onConnected) {
                this.onConnected();
              }
              this.controller.close();
            } else {
              this.statusMsg = RemoteSession.getInstance().statusText || '连接失败';
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('92%')
    .constraintSize({ maxWidth: 440 })
    .padding(16)
    .borderRadius(10)
    .backgroundColor(IdeTheme.palette().card)
    .border({ width: 1, color: IdeTheme.palette().border })
  }

  @Builder
  Field(label: string, value: string, onChange: (v: string) => void, placeholder: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(11)
        .fontColor(IdeTheme.palette().mutedForeground)
        .width('100%')
      TextInput({ text: value, placeholder: placeholder })
        .fontSize(13)
        .height(34)
        .backgroundColor(IdeTheme.palette().editor)
        .onChange(onChange)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
