# terminal-host

底栏终端 Web 宿主：vendored **xterm.js** + **FitAddon**。

- 前端：xterm 负责 VT 仿真、输入回显由 ArkTS `LocalTerminalService` 决策
- 后端：沙箱交互壳（`fileIo`），**不是** OS PTY
- 升级：用 `@xterm/xterm` / `@xterm/addon-fit` 覆盖 `vendor/`
