# hm-ide-agent 0.2.0

Scheme B 远端 Agent：绑定 `127.0.0.1`，WebSocket JSON-RPC。

## 构建

```bash
cargo build --release
./scripts/cross-build.sh   # → dist/hm-ide-agent-{x86_64,aarch64}-linux
```

## 运行

```bash
./target/release/hm-ide-agent --port 17821 [--token SECRET]
./target/release/hm-ide-agent --self-upgrade /path/to/new-binary   # 替换自身后退出
```

## 能力

- `fs.*` + `fs.watch` / `fs.search`
- `pty.*`
- `git.status` / `git.diff`（vendored libgit2）
- `task.run` / `task.kill`
- `session.hello` + session_token resume
- `agent.upgrade` / `POST /upgrade`

协议见 `../docs/remote-protocol.md`。
