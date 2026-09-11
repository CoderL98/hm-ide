# 获取 OHOS 版 LLVM / libclang

libclang 体积大，本仓库不内置二进制。

## 选项

1. **自建**：用与 DevEco 相同的 OHOS NDK clang 交叉编译 LLVM（`clang` 项目 `LLVM_ENABLE_PROJECTS=clang`，`CMAKE_TOOLCHAIN_FILE=ohos.toolchain.cmake`）。耗时长，产物巨大。
2. **发行版**：若团队已有内部 OHOS LLVM sysroot，设置：
   ```
   -DLLVM_ROOT=/path/to/llvm-ohos
   ```
   需包含 `include/clang-c/Index.h` 与 `lib/libclang.*`。
3. **仅主机诊断**：在 DevEco 所在 PC 用系统 libclang 做离线检查；设备 App 保持 stub。

启用后 `ClangService.diagnosticsFor()` 会向 Problems 面板注入 `.c/.cpp/.h` 诊断。
