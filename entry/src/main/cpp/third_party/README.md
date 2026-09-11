# third_party（设备端 SSH）

## libssh2（可选）

理想路径：将 **libssh2** 源码 vendoring 到 `libssh2/`，用 OHOS NDK 交叉编译，并在
`entry/src/main/cpp/CMakeLists.txt` 中设置 `-DHM_HAS_LIBSSH2=1` / `-DHM_LIBSSH2_ROOT=…`。

当前环境 **无法** 完成 OHOS NDK 链接验证，因此 `libhm_ssh.so` 保持完整 NAPI 表面 + ENOSYS。

## 主机真实自动部署（已实现）

| 工具 | 说明 |
|------|------|
| `tools/hm-ssh-helper` | Rust：detect arch → scp/SFTP → install → start → LocalForward |
| `tools/ssh-deploy-agent.sh` | Bash 封装；若 helper 已编译则委托之 |

IDE `SshDeployService` 驱动同一步骤并输出进度日志；设备上 native 失败时给出主机助手命令。
