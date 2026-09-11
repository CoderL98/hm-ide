import { ProblemItem, EditorTab } from '../models/FileNode';
import { ClangService } from './ClangService';

/**
 * 客户端启发式诊断（非真实语言服务）
 */
export class LintService {
  static lintTab(tab: EditorTab): ProblemItem[] {
    const out: ProblemItem[] = [];
    const content = tab.content ?? '';
    const file = tab.name;
    const path = tab.path;

    if (content.trim().length === 0) {
      out.push(new ProblemItem('warning', '文件为空', file, 1, path, 1));
      return out;
    }

    // 括号匹配启发式
    const pairs: string[][] = [['(', ')'], ['{', '}'], ['[', ']']];
    for (let pi = 0; pi < pairs.length; pi++) {
      const open = pairs[pi][0];
      const close = pairs[pi][1];
      let depth = 0;
      let lastOpenLine = 1;
      const lines = content.split('\n');
      for (let li = 0; li < lines.length; li++) {
        const line = lines[li];
        for (let ci = 0; ci < line.length; ci++) {
          const ch = line.charAt(ci);
          if (ch === open) {
            depth++;
            lastOpenLine = li + 1;
          } else if (ch === close) {
            depth--;
            if (depth < 0) {
              out.push(new ProblemItem('error', `多余的闭合括号 '${close}'`, file, li + 1, path, ci + 1));
              depth = 0;
            }
          }
        }
      }
      if (depth > 0) {
        out.push(new ProblemItem('error', `未匹配的开括号 '${open}'（约 ${depth} 处）`, file, lastOpenLine, path, 1));
      }
    }

    // 过长行
    const lines2 = content.split('\n');
    for (let li = 0; li < lines2.length; li++) {
      if (lines2[li].length > 160) {
        out.push(new ProblemItem('info', '行过长（>160）', file, li + 1, path, 161));
      }
    }

    // ArkTS：缺少 @Entry/@Component 提示（仅 .ets）
    if (tab.language === 'arkts' || file.endsWith('.ets')) {
      if (content.indexOf('struct ') >= 0 && content.indexOf('@Component') < 0 &&
        content.indexOf('@Entry') < 0) {
        out.push(new ProblemItem('warning', '检测到 struct，但未见 @Component / @Entry 装饰器', file, 1, path, 1));
      }
    }

    // libclang diagnostics for C/C++ (when LLVM_ROOT linked)
    if (ClangService.getInstance().isCppPath(path)) {
      const clangDiags = ClangService.getInstance().diagnosticsFor(path);
      for (let i = 0; i < clangDiags.length; i++) {
        out.push(clangDiags[i]);
      }
    }

    // 限制数量
    return out.slice(0, 40);
  }

  static lintTabs(tabs: EditorTab[]): ProblemItem[] {
    const all: ProblemItem[] = [];
    for (let i = 0; i < tabs.length; i++) {
      const items = LintService.lintTab(tabs[i]);
      for (let j = 0; j < items.length; j++) {
        all.push(items[j]);
      }
    }
    return all;
  }
}
