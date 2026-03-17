import { randomUUID } from "crypto";
import { CALL_TIMEOUT_MS, CONNECT_TIMEOUT_MS, STREAM_TIMEOUT_MS } from "./constants.ts";
import { Emitter } from "./events.ts";
import { CallError, ConnectionError, TimeoutError } from "./errors.ts";
import type { RpcRequest, TransportEvents } from "./types.ts";

interface PendingCall {
  method: string;
  resolve: (result: Record<string, unknown>) => void;
  reject: (error: Error) => void;
  timer: ReturnType<typeof setTimeout>;
  onProgress?: (event: string, data: Record<string, unknown>) => void;
}

export class WebSocketTransport extends Emitter<TransportEvents> {
  private socket: WebSocket | null = null;
  private pending = new Map<string, PendingCall>();
  private connected = false;

  get isConnected(): boolean {
    return this.connected;
  }

  async connect(port: number): Promise<void> {
    if (this.socket) {
      this.disconnect();
    }

    await new Promise<void>((resolve, reject) => {
      const socket = new WebSocket(`ws://127.0.0.1:${port}`);
      const timeout = setTimeout(() => {
        socket.close();
        reject(new ConnectionError(`Connection to port ${port} timed out`, port));
      }, CONNECT_TIMEOUT_MS);

      socket.onopen = () => {
        clearTimeout(timeout);
        this.connected = true;
        this.socket = socket;
        this.emit("open", undefined);
        resolve();
      };

      socket.onerror = () => {
        clearTimeout(timeout);
        reject(new ConnectionError(`Failed to connect to port ${port}`, port));
      };

      socket.onclose = (event) => {
        clearTimeout(timeout);
        const wasConnected = this.connected;
        this.connected = false;
        this.socket = null;
        this.rejectAllPending("Connection closed");
        if (wasConnected) {
          this.emit("close", { code: event.code, reason: event.reason });
        }
      };

      socket.onmessage = (event) => {
        this.handleMessage(String(event.data));
      };
    });
  }

  disconnect(): void {
    this.connected = false;
    if (this.socket) {
      this.socket.close();
      this.socket = null;
    }
    this.rejectAllPending("Disconnected");
  }

  call(
    method: string,
    params?: Record<string, unknown>,
    timeoutMs = CALL_TIMEOUT_MS,
  ): Promise<Record<string, unknown>> {
    return this.enqueue(method, params, timeoutMs);
  }

  callStreaming(
    method: string,
    params: Record<string, unknown> | undefined,
    onProgress: (event: string, data: Record<string, unknown>) => void,
    timeoutMs = STREAM_TIMEOUT_MS,
  ): Promise<Record<string, unknown>> {
    return this.enqueue(method, params, timeoutMs, onProgress);
  }

  private enqueue(
    method: string,
    params: Record<string, unknown> | undefined,
    timeoutMs: number,
    onProgress?: (event: string, data: Record<string, unknown>) => void,
  ): Promise<Record<string, unknown>> {
    if (!this.socket || !this.connected) {
      return Promise.reject(new ConnectionError("Not connected"));
    }

    return new Promise((resolve, reject) => {
      const id = randomUUID();
      const resetTimer = () =>
        setTimeout(() => {
          this.pending.delete(id);
          reject(new TimeoutError(method, timeoutMs));
        }, timeoutMs);

      let timer = resetTimer();
      this.pending.set(id, {
        method,
        resolve,
        reject,
        timer,
        onProgress: onProgress
          ? (event, data) => {
              clearTimeout(timer);
              timer = resetTimer();
              const pending = this.pending.get(id);
              if (pending) {
                pending.timer = timer;
              }
              onProgress(event, data);
            }
          : undefined,
      });

      const request: RpcRequest = { id, method, params };
      this.socket?.send(JSON.stringify(request));
    });
  }

  private handleMessage(raw: string): void {
    let payload: Record<string, unknown>;
    try {
      payload = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      return;
    }

    const id = payload.id as string | undefined;
    const event = payload.event as string | undefined;

    if (event && id) {
      this.pending.get(id)?.onProgress?.(event, (payload.data as Record<string, unknown>) ?? {});
      return;
    }

    if (event && !id) {
      this.emit("event", { event, data: (payload.data as Record<string, unknown>) ?? {} });
      return;
    }

    if (!id) {
      return;
    }

    const entry = this.pending.get(id);
    if (!entry) {
      return;
    }

    this.pending.delete(id);
    clearTimeout(entry.timer);

    if (payload.error) {
      entry.reject(new CallError(entry.method, String(payload.error)));
      return;
    }

    entry.resolve((payload.result as Record<string, unknown>) ?? {});
  }

  private rejectAllPending(reason: string): void {
    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timer);
      pending.reject(new ConnectionError(reason));
      this.pending.delete(id);
    }
  }
}
