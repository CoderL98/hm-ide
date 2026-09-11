/**
 * Native PTY NAPI module (libhm_pty.so)
 * Prefer this for local terminal; ArkTS falls back to sandbox shell on failure.
 */

export interface PtyResult {
  /** 0 = OK; otherwise see err */
  code: number;
  /** EPERM | ENOENT | ENOSYS | EINVAL | EIO | EBUSY | ESRCH | EUNKNOWN | OK */
  err: string;
  message: string;
  sessionId: number;
  ok: boolean;
  /** Only set by drain() */
  data?: string;
}

export interface HmPtyNative {
  /** Probe /dev/ptmx without forking */
  available(): PtyResult;
  /** Start PTY session; optional cwd / shell path */
  start(cols?: number, rows?: number, cwd?: string, shell?: string): PtyResult;
  /** Write stdin bytes (UTF-8 string) */
  write(sessionId: number, data: string): PtyResult;
  /** Drain buffered master output since last drain */
  drain(sessionId: number): PtyResult;
  /** ioctl TIOCSWINSZ */
  resize(sessionId: number, cols: number, rows: number): PtyResult;
  /** SIGHUP/SIGTERM then close */
  kill(sessionId: number): PtyResult;
}

declare const hmPty: HmPtyNative;
export default hmPty;
