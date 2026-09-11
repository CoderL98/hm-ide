# 第三方原生依赖（OHOS NDK 预编译）

本目录**不提交**巨型预编译包。DevEco 构建 `entry` 时默认以 **stub** 模式编译：

| 模块 | 产物 | 默认 | 启用方式 |
|------|------|------|----------|
| PTY | `libhm_pty.so` | **完整实现** | 无需额外库（设备 SELinux 可能仍拒 `/dev/ptmx`） |
| Git | `libhm_git.so` | stub（ENOSYS） | `-DHM_GIT2_ROOT=/path/to/libgit2-prefix` |
| Clang | `libhm_clang.so` | stub（ENOSYS） | `-DLLVM_ROOT=/path/to/llvm-prefix` |

## libgit2（推荐静态库）

1. 获取源码：`git clone https://github.com/libgit2/libgit2.git`（建议 v1.7.x / v1.8.x）。
2. 使用 **HarmonyOS NDK** 工具链交叉编译（示例见 `../scripts/build-libgit2-ohos.sh`）。
3. 安装前缀形如：
   ```
   native/third_party/libgit2-ohos/
     include/git2.h
     lib/libgit2.a
   ```
4. 在 `entry/build-profile.json5` → `externalNativeOptions.arguments` 增加：
   ```
   -DHM_GIT2_ROOT=/绝对路径/hm-ide/native/third_party/libgit2-ohos
   ```
5. 重新 Sync / Build。`GitService.probe()` 应返回 `ok: true`。

> HTTPS clone 还需 OpenSSL/mbedTLS 与证书路径；先从本地 `init/status/commit` 打通。

## libclang / LLVM（体积警告）

- 完整 libclang + 相关 LLVM 库对移动端 **体积很大**（数十～上百 MB）。
- 仅建议桌面 2in1 / 调试包链接；Release 可继续 stub。
- 交叉编译 LLVM 超出本仓库脚本能力时，请使用官方/自建 OHOS LLVM 发行版，保证存在：
  ```
  $LLVM_ROOT/include/clang-c/Index.h
  $LLVM_ROOT/lib/libclang.so  (或 .a)
  ```
- CMake：`-DLLVM_ROOT=/绝对路径/...`
- 脚本占位：`../scripts/fetch-llvm-ohos.md`

## 与 DevEco 联调

```text
entry/build-profile.json5
  buildOption.externalNativeOptions.arguments:
    -DHM_GIT2_ROOT=... -DLLVM_ROOT=...
```

未设置时工程仍可编译运行：PTY 真逻辑 + Git/Clang 诚实 ENOSYS 回退。
