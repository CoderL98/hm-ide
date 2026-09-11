export interface ClangNativeResult {
  code: number;
  err: string;
  message: string;
  data: string;
  ok: boolean;
}

export interface HmClangNative {
  available(): ClangNativeResult;
  parseFile(path: string, argsJson?: string): ClangNativeResult;
  diagnostics(path: string, argsJson?: string): ClangNativeResult;
}

declare const hmClang: HmClangNative;
export default hmClang;
