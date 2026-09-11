# 鸿蒙原生IDE（hm-ide）— Scheme B（B1+B2）

HarmonyOS NEXT（API 12+）Stage 模型 IDE：**本地 App = 编辑器壳**，**远端 Linux = Rust `hm-ide-agent`**（文件系统、真实 PTY、监视/搜索、Git、任务）。经 **SSH LocalForward** 访问；Agent **只绑 `127.0.0.1`**。不是 DevEco 编译器替代品，也 **不做 SSH 网关产品**。

## 快速理解

| 侧 | 职责 |
|----|------|
| HarmonyOS App | Monaco、资源管理器、搜索/SCM/构建、终端 UI、连接对话框 |
| `hm-ide-agent` 0.2.0 | `fs.*` / `pty.*` / `git.*` / `task.*` JSON-RPC over WebSocket |
| SSH | 上传二进制、`nohup` 启动、`-L` 转发端口 |

默认 UX：**「打开远程文件夹」**；本地沙箱示例为次要。

## 用 DevEco Studio 打开

1. 安装 DevEco Studio（API 12 / HarmonyOS NEXT + NDK）。
2. **File → Open** 本仓库根（含 `build-profile.json5`）。
3. 同步后运行 `entry`。

### Native so

| so | 默认 | 说明 |
|----|------|------|
| `libhm_pty.so` | 完整 | 本地 PTY（次要；常被 SELinux 拒） |
| `libhm_ssh.so` | **完整 NAPI + ENOSYS** | 设备端未链 libssh2；主机用 helper |
| `libhm_git.so` / `libhm_clang.so` | stub | 可选；相对 Agent 降级 |

## 远程 Agent

```bash
cd agent
cargo build --release
./scripts/cross-build.sh          # x86_64 + aarch64 → agent/dist/
./target/release/hm-ide-agent --port 17821

# 冒烟（需先启动 agent）
pip install websocket-client   # 或 --break-system-packages
python3 tools/agent-smoke-test.py
# 覆盖：hello/resume、fs、watch、search、git、task、pty
```

安装约定：`~/.hm-ide-agent/bin/hm-ide-agent`  
协议：[`docs/remote-protocol.md`](./docs/remote-protocol.md)  
Agent README：[`agent/README.md`](./agent/README.md)

### 主机真实自动部署（推荐路径）

设备端 `libhm_ssh` 在未链接 OHOS 版 libssh2 前返回 ENOSYS。**主机 OpenSSH 路径已完整可用：**

```bash
# 编译桌面 helper（可选，脚本会优先调用）
cd tools/hm-ssh-helper && cargo build --release && cd ../..

tools/ssh-deploy-agent.sh -h 192.168.1.10 -u dev -r /home/dev/proj -a 17821
# 步骤：detect arch → scp → install → start → LocalForward（阻塞）
# IDE「打开远程文件夹」填同一主机；WS: ws://127.0.0.1:17821/ws

# 版本不匹配强制替换：
tools/ssh-deploy-agent.sh -h … -u … -r … -f
# 或 helper：hm-ssh-helper upgrade --host … --user … --binary agent/dist/hm-ide-agent-x86_64-linux
```

IDE `SshDeployService` 按相同步骤输出进度日志，并在 native 失败时给出上述命令。

## 架构路径

| 路径 | 说明 |
|------|------|
| `agent/` | Rust hm-ide-agent 0.2.0 |
| `docs/remote-protocol.md` | 远程协议 |
| `tools/ssh-deploy-agent.sh` | 主机部署 + 转发 |
| `tools/hm-ssh-helper/` | Rust SSH/SFTP helper |
| `entry/.../services/remote/` | AgentClient / RemoteFs / RemoteSession / SshDeployService |
| `entry/.../cpp/ssh/` | hm_ssh NAPI 表面（ENOSYS） |

详见 [PLAN.md](./PLAN.md)、[TODO.md](./TODO.md)。

## 已知限制 / Stub

- **设备端完整 libssh2（SFTP + LocalForward）未在 OHOS NDK 链上验证** → `libhm_ssh.so` 返回 `ENOSYS`；请用主机脚本 / `hm-ssh-helper` 或手动 `ssh -L`。
- 本地 PTY / 设备端 libgit2 / libclang / hvigor 相对远程 Agent **次要或推迟**。
- Agent 不监听公网；务必经 SSH 隧道。

## 许可证

MIT © CoderL98
