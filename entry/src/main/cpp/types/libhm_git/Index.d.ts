export interface GitNativeResult {
  code: number;
  err: string;
  message: string;
  data: string;
  ok: boolean;
}

export interface HmGitNative {
  available(): GitNativeResult;
  init(path: string): GitNativeResult;
  open(path: string): GitNativeResult;
  close(): GitNativeResult;
  status(): GitNativeResult;
  add(pathspec: string): GitNativeResult;
  commit(message: string, authorName?: string, authorEmail?: string): GitNativeResult;
  clone(url: string, path: string): GitNativeResult;
  fetch(remote?: string): GitNativeResult;
  pull(remote?: string, branch?: string): GitNativeResult;
  diffSummary(): GitNativeResult;
  currentBranch(): GitNativeResult;
}

declare const hmGit: HmGitNative;
export default hmGit;
