import type { Connection } from "vscode-languageserver";
import type { ServerTraceLevel } from "./config.js";

// 日志封装：info/warn/error → connection.console，trace → connection.tracer
export class Logger {
  private _level: ServerTraceLevel;

  constructor(
    private connection: Connection,
    level: ServerTraceLevel = "off",
  ) {
    this._level = level;
  }

  // trace 仅在 messages 或 verbose 级别时输出
  get traceEnabled(): boolean {
    return this._level === "messages" || this._level === "verbose";
  }

  setLevel(level: ServerTraceLevel): void {
    this._level = level;
  }

  info(message: string): void {
    this.connection.console.info(`[MoonParse] ${message}`);
  }

  warn(message: string): void {
    this.connection.console.warn(`[MoonParse] ${message}`);
  }

  error(message: string): void {
    this.connection.console.error(`[MoonParse] ${message}`);
  }

  trace(message: string): void {
    if (this.traceEnabled) {
      this.connection.tracer.log(message);
    }
  }

  // 遥测事件
  telemetry(event: string, data?: Record<string, unknown>): void {
    this.connection.telemetry.logEvent({
      event,
      ...(data ?? {}),
    });
  }
}
