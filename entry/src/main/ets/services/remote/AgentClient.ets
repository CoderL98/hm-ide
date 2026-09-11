import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

export type JsonValue = Object | null | string | number | boolean;

export interface RpcError {
  code: number;
  message: string;
}

export type NotificationHandler = (method: string, params: Object) => void;

/**
 * WebSocket JSON-RPC client for hm-ide-agent.
 * Connects to ws://127.0.0.1:PORT/ws after SSH LocalForward.
 */
export class AgentClient {
  private static nextId: number = 1;
  private ws: webSocket.WebSocket | null = null;
  private pending: Map<number, { resolve: (v: Object) => void; reject: (e: Error) => void }> =
    new Map();
  private notifyHandlers: NotificationHandler[] = [];
  private closeHandlers: Array<() => void> = [];
  private url: string = '';
  connected: boolean = false;
  lastError: string = '';

  onNotification(handler: NotificationHandler): void {
    this.notifyHandlers.push(handler);
  }

  onClose(handler: () => void): void {
    this.closeHandlers.push(handler);
  }

  clearNotificationHandlers(): void {
    this.notifyHandlers = [];
  }

  async connect(url: string, token?: string): Promise<void> {
    await this.disconnect();
    let full = url;
    if (token && token.length > 0) {
      full = url.indexOf('?') >= 0 ? `${url}&token=${token}` : `${url}?token=${token}`;
    }
    this.url = full;
    this.lastError = '';

    return new Promise<void>((resolve, reject) => {
      try {
        const ws = webSocket.createWebSocket();
        this.ws = ws;

        ws.on('open', (_err: BusinessError, _value: Object) => {
          this.connected = true;
          resolve();
        });

        ws.on('message', (_err: BusinessError, value: string | ArrayBuffer) => {
          const text = typeof value === 'string' ? value : '';
          if (text) {
            this.handleMessage(text);
          }
        });

        ws.on('close', () => {
          this.connected = false;
          this.rejectAll(new Error('websocket closed'));
          for (let i = 0; i < this.closeHandlers.length; i++) {
            try {
              this.closeHandlers[i]();
            } catch (_e) {
              // ignore
            }
          }
        });

        ws.on('error', (err: BusinessError) => {
          this.lastError = `${err.code}: ${err.message}`;
          this.connected = false;
          reject(new Error(this.lastError));
        });

        ws.connect(full).catch((e: BusinessError) => {
          this.lastError = `${e.code}: ${e.message}`;
          reject(new Error(this.lastError));
        });
      } catch (e) {
        reject(e instanceof Error ? e : new Error(String(e)));
      }
    });
  }

  async disconnect(): Promise<void> {
    this.rejectAll(new Error('disconnect'));
    if (this.ws) {
      try {
        await this.ws.close();
      } catch (_e) {
        // ignore
      }
      this.ws = null;
    }
    this.connected = false;
  }

  private rejectAll(err: Error): void {
    this.pending.forEach((p) => p.reject(err));
    this.pending.clear();
  }

  private handleMessage(text: string): void {
    let msg: Record<string, Object>;
    try {
      msg = JSON.parse(text) as Record<string, Object>;
    } catch (_e) {
      return;
    }
    if (msg['method'] !== undefined && msg['id'] === undefined) {
      const method = String(msg['method']);
      const params = (msg['params'] as Object) ?? {};
      for (let i = 0; i < this.notifyHandlers.length; i++) {
        try {
          this.notifyHandlers[i](method, params);
        } catch (_e) {
          // ignore handler errors
        }
      }
      return;
    }
    const id = msg['id'] as number;
    const p = this.pending.get(id);
    if (!p) {
      return;
    }
    this.pending.delete(id);
    if (msg['error']) {
      const er = msg['error'] as Record<string, Object>;
      p.reject(new Error(`${er['code']}: ${er['message']}`));
    } else {
      p.resolve((msg['result'] as Object) ?? {});
    }
  }

  request(method: string, params: Object = {}): Promise<Object> {
    if (!this.ws || !this.connected) {
      return Promise.reject(new Error('agent not connected'));
    }
    const id = AgentClient.nextId++;
    const payload = JSON.stringify({ id, method, params });
    return new Promise<Object>((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws!.send(payload).catch((e: BusinessError) => {
        this.pending.delete(id);
        reject(new Error(`${e.code}: ${e.message}`));
      });
    });
  }
}
