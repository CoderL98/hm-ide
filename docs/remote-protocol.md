# 远程协议（Scheme B / B1+B2）

鸿蒙 IDE（本地编辑器壳）通过 **SSH LocalForward** 连接远端 Linux 上的 **hm-ide-agent**。  
Agent **只监听 `127.0.0.1`**，传输为 **WebSocket + JSON-RPC 风格** 文本帧。

- Endpoint：`ws://127.0.0.1:{port}/ws`
- 可选：`?token=...`（与 `--token` 一致）
- 协议标识：`hm-ide-remote/0.2`
- Agent 版本：semver（`session.hello.version`，当前 **0.2.0**）

## 消息格式

**请求**

```json
{ "id": 1, "method": "fs.list", "params": { "path": "/home/u/proj" } }
```

**成功响应**

```json
{ "id": 1, "result": { ... } }
```

**错误响应**

```json
{ "id": 1, "error": { "code": -32000, "message": "..." } }
```

**服务端推送（无 id）**

```json
{ "method": "pty.data", "params": { "ptyId": "...", "encoding": "utf8", "data": "..." } }
```

## 方法一览

| 方法 | 参数 | 结果 | 说明 |
|------|------|------|------|
| `session.hello` | `{ sessionToken? }` | `{ version, os, arch, pid, protocol, session_token, resumed }` | 握手；可带上次 token 尝试 resume |
| `fs.list` | `{ path }` | `{ entries: [{ name, path, is_dir, size, mtime_ms }] }` | 列目录 |
| `fs.read` | `{ path, encoding? }` | `{ path, encoding, data, size }` | `utf8`（默认）或 `base64` |
| `fs.write` | `{ path, data, encoding? }` | `{ path, size }` | 写文件（自动建父目录） |
| `fs.mkdir` | `{ path }` | `{ path }` | 递归建目录 |
| `fs.remove` | `{ path, recursive? }` | `{ path, ok }` | 默认 recursive=true |
| `fs.rename` | `{ from, to }` | `{ from, to }` | 移动/重命名 |
| `fs.stat` | `{ path }` | `{ path, is_dir, is_file, size, mtime_ms, mode }` | 元数据 |
| `fs.watch` | `{ path, recursive? }` | `{ watchId, path, recursive }` | 监视目录（notify） |
| `fs.unwatch` | `{ watchId }` | `{ ok, watchId }` | 取消监视 |
| `fs.search` | `{ path, query, maxHits?, regex?, caseInsensitive? }` | `{ hits, truncated, count }` | ripgrep 风格搜索（ignore 大目录） |
| `git.status` | `{ path }` | `{ branch, commit, workdir, items, clean }` | libgit2 状态 |
| `git.diff` | `{ path }` | `{ filesChanged, insertions, deletions, files }` | 相对 HEAD 的 diff 摘要 |
| `task.run` | `{ command, cwd?, shell? }` | `{ taskId, command, cwd }` | 在工作区 cwd 启动命令 |
| `task.kill` | `{ taskId }` | `{ ok, taskId }` | 终止任务 |
| `agent.upgrade` | `{ path }` | `{ ok, message }` | 用已上传的新二进制替换自身并退出 |
| `pty.open` | `{ cols, rows, cwd?, shell? }` | `{ ptyId, cols, rows }` | 真实 PTY |
| `pty.write` | `{ ptyId, data, encoding? }` | `{ ok }` | 写入 PTY |
| `pty.resize` | `{ ptyId, cols, rows }` | `{ ok }` | 调整窗口 |
| `pty.close` | `{ ptyId }` | `{ ok }` | 关闭会话 |

HTTP：

| 路径 | 说明 |
|------|------|
| `GET /health` | `{ ok, version, protocol, pid }` |
| `POST /upgrade` | body `{ path }` — 同 `agent.upgrade`，替换后进程退出 |

CLI：`--port`、`--token`、`--self-upgrade <path>`、`--version`

## 推送事件

| 方法 | 参数 | 说明 |
|------|------|------|
| `pty.data` | `{ ptyId, encoding, data }` | PTY 输出 |
| `pty.exit` | `{ ptyId }` | 读端 EOF |
| `fs.changed` | `{ watchId, kind, paths, root }` | 文件变更 |
| `task.output` | `{ taskId, stream, data }` | 任务 stdout/stderr |
| `task.exit` | `{ taskId, code }` | 任务结束 |

## 部署约定

| 项 | 值 |
|----|-----|
| 安装路径 | `~/.hm-ide-agent/bin/hm-ide-agent` |
| 默认端口 | `17821` |
| 日志 | stderr / `RUST_LOG` / `~/.hm-ide-agent/agent.log` |
| 多架构 | `x86_64` + `aarch64` Linux |

### 真实自动部署路径（主机 OpenSSH）

```bash
# 推荐：Bash 封装（有 helper 则委托）
tools/ssh-deploy-agent.sh -h HOST -u USER -r /path/to/proj -a 17821

# 或直接 Rust helper
tools/hm-ssh-helper/target/release/hm-ssh-helper deploy \
  --host HOST --user USER --remote-path /path/to/proj --agent-port 17821
```

步骤：① detect arch → ② scp/SFTP 上传匹配二进制 → ③ install 到 `~/.hm-ide-agent/bin/` →  
④ `nohup` 启动（`--port`/`--token`）→ ⑤ SSH LocalForward → ⑥ IDE `session.hello`；  
版本不匹配时 `-f` 强制上传或 `agent.upgrade` / helper `upgrade`。

### 设备端 libhm_ssh

NAPI 表面完整（detect/upload/start/forward/replace/deployAll），默认 **ENOSYS**（OHOS NDK 未链接 libssh2）。  
见 `entry/src/main/cpp/third_party/README.md`。

## 错误码

| code | 含义 |
|------|------|
| -32700 | JSON 解析失败 |
| -32601 | 方法不存在 |
| -32602 | 参数无效 |
| -32000 | 业务/IO 错误 |
