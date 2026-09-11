/**
 * ArkTS facade for libhm_clang.so (libclang NAPI).
 * Diagnostics JSON → ProblemItem for .c/.cpp/.h when LLVM_ROOT linked.
 */
import hmClang from 'libhm_clang.so';
import { ProblemItem } from '../models/FileNode';

export interface ClangResult {
  code: number;
  err: string;
  message: string;
  data: string;
  ok: boolean;
}

export class ClangService {
  private static instance: ClangService = new ClangService();
  libclangLinked: boolean = false;
  lastError: string = '';

  static getInstance(): ClangService {
    return ClangService.instance;
  }

  private wrap(r: Object): ClangResult {
    const o = r as Record<string, Object>;
    return {
      code: Number(o['code'] ?? 99),
      err: String(o['err'] ?? 'EUNKNOWN'),
      message: String(o['message'] ?? ''),
      data: String(o['data'] ?? '[]'),
      ok: Boolean(o['ok'] ?? false)
    };
  }

  probe(): ClangResult {
    try {
      const r = this.wrap(hmClang.available());
      this.libclangLinked = r.ok;
      if (!r.ok) {
        this.lastError = `${r.err}: ${r.message}`;
      }
      return r;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.libclangLinked = false;
      this.lastError = msg;
      return { code: 3, err: 'ENOSYS', message: msg, data: '{"libclang":false}', ok: false };
    }
  }

  isCppPath(path: string): boolean {
    const lower = path.toLowerCase();
    return lower.endsWith('.c') || lower.endsWith('.cc') || lower.endsWith('.cpp') ||
      lower.endsWith('.cxx') || lower.endsWith('.h') || lower.endsWith('.hpp') ||
      lower.endsWith('.hxx');
  }

  /** Returns ProblemItems from libclang; empty if not linked / parse fail */
  diagnosticsFor(path: string, extraArgsJson: string = '[]'): ProblemItem[] {
    if (!this.isCppPath(path)) {
      return [];
    }
    this.probe();
    if (!this.libclangLinked) {
      return [];
    }
    try {
      const r = this.wrap(hmClang.diagnostics(path, extraArgsJson));
      if (!r.ok || !r.data) {
        return [];
      }
      const arr = JSON.parse(r.data) as Object[];
      const out: ProblemItem[] = [];
      for (let i = 0; i < arr.length; i++) {
        const it = arr[i] as Record<string, Object>;
        const file = String(it['file'] ?? path);
        const name = file.indexOf('/') >= 0 ? file.substring(file.lastIndexOf('/') + 1) : file;
        out.push(new ProblemItem(
          String(it['severity'] ?? 'info'),
          String(it['message'] ?? ''),
          name,
          Number(it['line'] ?? 1),
          file,
          Number(it['column'] ?? 1)
        ));
      }
      return out;
    } catch (_e) {
      return [];
    }
  }

  capabilityLabel(): string {
    return this.libclangLinked ? 'libclang 诊断' : 'libclang 未链接';
  }
}
