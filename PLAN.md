# 鸿蒙原生IDE（hm-ide）规划

## 目标

在 HarmonyOS NEXT（API 12+）Stage 模型上交付原生 IDE：**本地 = 编辑器壳（Monaco / UI）**，**远程 = Rust `hm-ide-agent`（FS + PTY + watch/search/git/task）**，经 **SSH LocalForward** 连接。视觉对齐 `design/prototypes/`。

## 架构（Scheme B）

```
HarmonyOS App (entry)
  ├── Monaco / Explorer / Terminal / Search / SCM / Build
  ├── AgentClient  ──WS JSON-RPC──►  127.0.0.1:PORT  (SSH -L)
  ├── RemoteFs / RemoteSession（watch、重连、草稿）
  └── SshDeployService ──(hm_ssh ENOSYS / host helper)──► upload + LocalForward

Linux 开发机
  ~/.hm-ide-agent/bin/hm-ide-agent   # bind 127.0.0.1 only
       ├── fs.* / fs.watch / fs.search
       ├── pty.* + pty.data
       ├── git.status / git.diff
       └── task.run / task.kill + task.output/exit
```

## 当前里程碑（B1+B2）

- [x] Agent 0.2.0：watch、search、git2、task、session resume、self-upgrade
- [x] 主机真实自动部署：`tools/hm-ssh-helper` + `ssh-deploy-agent.sh`
- [x] IDE：远程搜索 / SCM / Tasks / 重连 / 草稿 / 部署步骤日志
- [ ] 设备端 libssh2 链接（NAPI 表面已就绪，实现待 OHOS NDK）

## 范围外

完整 DevEco 替代、插件市场、完整 DAP、SSH **网关即产品**。
