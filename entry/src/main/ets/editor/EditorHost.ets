/**
 * 编辑器宿主抽象 — 可替换为原生实现或其它 Web 引擎
 */
export interface EditorHost {
  setValue(text: string): void;
  getValue(): Promise<string>;
  setLanguage(lang: string): void;
  setTheme(theme: string): void;
  setFontSize(size: number): void;
  setTabSize(size: number): void;
  focus(): void;
  /** 触发查找 / 替换（Monaco actions） */
  triggerFind(): void;
  triggerReplace(): void;
  /** 跳转到行:列（1-based） */
  revealLine(line: number, column?: number): void;
}

export type EditorChangeHandler = (value: string) => void;
export type EditorReadyHandler = (engine: string) => void;
export type EditorSaveHandler = () => void;
