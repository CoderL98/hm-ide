/**
 * ArkTS wrapper around libhm_pty.so (Native C++ NAPI PTY).
 * Loads the shared library at module init; probe via available().
 */
import hmPty from 'libhm_pty.so';

export interface NativePtyResult {
  code: number;
  err: string;
  message: string;
  sessionId: number;
  ok: boolean;
  data?: string;
}

export class NativePtyService {
  private static instance: NativePtyService = new NativePtyService();
  private loadError: string = '';
  private usable: boolean = true;

  static getInstance(): NativePtyService {
    return NativePtyService.instance;
  }

  /** Soft probe — native always loads; ptmx may still fail at runtime. */
  available(): NativePtyResult {
    try {
      const r = hmPty.available() as NativePtyResult;
      return r;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.usable = false;
      this.loadError = msg;
      return {
        code: 3,
        err: 'ENOSYS',
        message: `native module unavailable: ${msg}`,
        sessionId: -1,
        ok: false
      };
    }
  }

  isModuleLoaded(): boolean {
    return this.usable;
  }

  getLoadError(): string {
    return this.loadError;
  }

  start(cols: number, rows: number, cwd?: string, shell?: string): NativePtyResult {
    try {
      return hmPty.start(cols, rows, cwd ?? '', shell ?? '') as NativePtyResult;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return { code: 99, err: 'EUNKNOWN', message: msg, sessionId: -1, ok: false };
    }
  }

  write(sessionId: number, data: string): NativePtyResult {
    try {
      return hmPty.write(sessionId, data) as NativePtyResult;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return { code: 99, err: 'EUNKNOWN', message: msg, sessionId: sessionId, ok: false };
    }
  }

  drain(sessionId: number): NativePtyResult {
    try {
      return hmPty.drain(sessionId) as NativePtyResult;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return { code: 99, err: 'EUNKNOWN', message: msg, sessionId: sessionId, ok: false, data: '' };
    }
  }

  resize(sessionId: number, cols: number, rows: number): NativePtyResult {
    try {
      return hmPty.resize(sessionId, cols, rows) as NativePtyResult;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return { code: 99, err: 'EUNKNOWN', message: msg, sessionId: sessionId, ok: false };
    }
  }

  kill(sessionId: number): NativePtyResult {
    try {
      return hmPty.kill(sessionId) as NativePtyResult;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return { code: 99, err: 'EUNKNOWN', message: msg, sessionId: sessionId, ok: false };
    }
  }
}
