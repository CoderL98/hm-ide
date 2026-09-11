# TODO — 鸿蒙原生IDE（Scheme B / B1+B2）

## 工程骨架

- [x] DevEco Stage 模型工程结构
- [x] API 12+ / Native CMake / LICENSE / prototypes

## Scheme B — 远程 Agent（主路径）

- [x] Rust crate `agent/`（hm-ide-agent）Tokio + axum WS
- [x] JSON-RPC：`session.hello` / `fs.*` / `pty.*` + 推送
- [x] 仅绑定 127.0.0.1；CLI `--port` `--token` `--self-upgrade`
- [x] 多架构：x86_64 + aarch64 → `agent/dist/`
- [x] `docs/remote-protocol.md`（中文 + 方法表）
- [x] `tools/ssh-deploy-agent.sh` + `tools/hm-ssh-helper` + smoke tests
- [x] ArkTS `AgentClient` / `RemoteFs` / `RemoteSession`
- [x] UI「打开远程文件夹」；欢迎页主 CTA；状态栏 `SSH: user@host`
- [x] Explorer/Editor/Terminal 远程会话走 RemoteFs / Agent PTY
- [x] `SshDeployService` 端到端步骤日志 + `libhm_ssh.so` 完整 NAPI 表面（ENOSYS）
- [x] **B1** `fs.watch`/`fs.unwatch` + `fs.changed`；reconnect+session token；`fs.search`
- [x] **B1 IDE** 订阅 watch、自动重连退避、离线草稿、远程搜索面板
- [x] **B2** `git.status`/`git.diff`（git2）；`task.run`/`task.kill` + 推送；`agent.upgrade`
- [x] **B2 IDE** SCM 走远程 git；Build 面板远程 task；版本不匹配升级路径
- [ ] 真机 OHOS NDK 链接 libssh2 实现 SFTP/LocalForward（主机路径已可用）

## 自适应 UI / 编辑器

- [x] 多设备壳层 / Monaco / 查找替换

## 本地能力（次要 / 推迟相对 Agent）

- [x] 沙箱工作区 CRUD（演示用）
- [x] Native PTY / 沙箱壳回退（次要）
- [x] Git / Clang / Hvigor 脚手架（次要；完整链接仍待本机 NDK）
- [ ] 多工作区根
- [ ] 真机验证 ptmx

## 范围外（明确不做）

- [ ] 完整设备端 DevEco 替代（无远程）
- [ ] 插件市场
- [ ] 完整调试器 DAP
- [ ] SSH 网关即产品（Agent 即远端）
