# Native NAPI 模块

| 目标 | so | 源码 |
|------|-----|------|
| PTY | `libhm_pty.so` | `napi_init.cpp`, `pty_session.cpp` |
| Git | `libhm_git.so` | `git/` |
| Clang | `libhm_clang.so` | `clang/` |

CMake 入口：本目录 `CMakeLists.txt`（由 `entry/build-profile.json5` `externalNativeOptions` 引用）。

可选参数：

- `-DHM_GIT2_ROOT=...` 启用 libgit2
- `-DLLVM_ROOT=...` 启用 libclang

详见仓库 `native/third_party/README.md`。


## libhm_ssh.so (Scheme B stub)

`ssh/napi_ssh_init.cpp` — ENOSYS stub for SFTP upload / SSH LocalForward.
Real libssh integration TBD. Host helper: `tools/ssh-deploy-agent.sh`.
