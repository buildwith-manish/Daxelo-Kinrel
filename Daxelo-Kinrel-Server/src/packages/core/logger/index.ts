/**
 * KINREL Mirror — Core Logger
 * Structured JSON logger with severity levels and context tracking.
 */

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

interface LogEntry {
  timestamp: string;
  level: LogLevel;
  message: string;
  context?: string;
  traceId?: string;
  userId?: string;
  [key: string]: unknown;
}

const LOG_LEVEL_PRIORITY: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

class Logger {
  private minLevel: LogLevel;
  private defaultContext: Record<string, unknown>;

  constructor(minLevel: LogLevel = 'info', defaultContext: Record<string, unknown> = {}) {
    this.minLevel = minLevel;
    this.defaultContext = defaultContext;
  }

  private shouldLog(level: LogLevel): boolean {
    return LOG_LEVEL_PRIORITY[level] >= LOG_LEVEL_PRIORITY[this.minLevel];
  }

  private formatEntry(level: LogLevel, message: string, data?: Record<string, unknown>): LogEntry {
    return {
      timestamp: new Date().toISOString(),
      level,
      message,
      ...this.defaultContext,
      ...data,
    };
  }

  private output(entry: LogEntry): void {
    const output = JSON.stringify(entry);
    switch (entry.level) {
      case 'debug':
      case 'info':
        console.log(output);
        break;
      case 'warn':
        console.warn(output);
        break;
      case 'error':
        console.error(output);
        break;
    }
  }

  debug(message: string, data?: Record<string, unknown>): void {
    if (!this.shouldLog('debug')) return;
    this.output(this.formatEntry('debug', message, data));
  }

  info(message: string, data?: Record<string, unknown>): void {
    if (!this.shouldLog('info')) return;
    this.output(this.formatEntry('info', message, data));
  }

  warn(message: string, data?: Record<string, unknown>): void {
    if (!this.shouldLog('warn')) return;
    this.output(this.formatEntry('warn', message, data));
  }

  error(message: string, data?: Record<string, unknown>): void {
    if (!this.shouldLog('error')) return;
    this.output(this.formatEntry('error', message, data));
  }

  child(context: Record<string, unknown>): Logger {
    return new Logger(this.minLevel, { ...this.defaultContext, ...context });
  }
}

export const logger = new Logger(
  (process.env.LOG_LEVEL as LogLevel) || 'info',
  { service: 'kinrel-mirror', version: '1.0.0' }
);

export { Logger };
