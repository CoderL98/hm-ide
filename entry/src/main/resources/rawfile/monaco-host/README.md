# Monaco Host（本地 rawfile）

本目录由 Web 组件加载，路径：`resource://rawfile/monaco-host/index.html`。

## 已包含

- `vs/` — monaco-editor@0.52.2 的 `min/vs` AMD 构建（本地离线）
- `index.html` / `bridge.js` / `boot.js` — 宿主与 ArkTS 桥接
- `boot.js` 注册语言 `arkts`（Monarch：TypeScript 基 + Harmony 装饰器高亮），`.ets` 映射到它

## ArkTS 桥接 API

**Web → 原生（JavaScriptProxy `IdeBridge`）**

| 方法 | 参数 | 说明 |
|------|------|------|
| `onReady` | JSON `{engine}` | 编辑器就绪 |
| `onChange` | string | 内容变更 |
| `onSaveRequest` | string | Ctrl/Cmd+S |

**原生 → Web（`controller.runJavaScript`）**

```js
window.__hmIde.setValue("...");
window.__hmIde.getValue();
window.__hmIde.setLanguage("arkts"); // arkts | typescript | json | ...
window.__hmIde.setTheme("dark"); // dark|light|vs-dark|vs
window.__hmIde.setFontSize(14);
window.__hmIde.setTabSize(2);
window.__hmIde.focus();
window.__hmIde.triggerFind();    // Monaco actions.find
window.__hmIde.triggerReplace(); // Find/Replace
window.__hmIde.revealLine(12, 1);
window.__hmIde.dump();
```

## 升级 Monaco

```bash
npm pack monaco-editor@<version>
# 解压后用 package/min/vs 覆盖本目录 vs/
```

若 Web 组件无法跑 AMD，`boot.js` 会自动切到高保真 textarea fallback（视觉对齐原型）。
