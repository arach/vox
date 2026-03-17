export class VoxError extends Error {
  constructor(message: string) {
    super(message);
    this.name = new.target.name;
  }
}

export class ServiceUnavailableError extends VoxError {
  constructor(message = "Vox daemon is not running.") {
    super(message);
  }
}

export class ConnectionError extends VoxError {
  constructor(message: string, readonly port?: number) {
    super(message);
  }
}

export class TimeoutError extends VoxError {
  constructor(readonly method: string, readonly timeoutMs: number) {
    super(`Timed out waiting for ${method} after ${timeoutMs}ms`);
  }
}

export class CallError extends VoxError {
  constructor(readonly method: string, message: string) {
    super(message);
  }
}
