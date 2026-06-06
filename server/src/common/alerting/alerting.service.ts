import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { LoggerService } from '../logger/logger.service';

/**
 * Sliding window entry for tracking request metrics.
 */
interface WindowEntry {
  timestamp: number;
  isError: boolean;
  duration: number;
}

/**
 * Alerting service — tracks error rate and p99 latency in a sliding window.
 *
 * - Maintains a sliding window of the last 5 minutes of request data
 * - Triggers alert if error rate > threshold (default 1%, configurable via ERROR_RATE_ALERT_THRESHOLD)
 * - Triggers alert if p99 latency > threshold (default 2s, configurable via P99_ALERT_THRESHOLD_MS)
 * - Alerts are structured logs (can be connected to Logtail/Datadog/PagerDuty later)
 * - `checkAlerts()` called on every error
 */
@Injectable()
export class AlertingService {
  private readonly windowMs: number = 5 * 60 * 1000; // 5 minutes
  private readonly errorRateThreshold: number;
  private readonly p99ThresholdMs: number;

  // Track all request durations (populated by recordRequest)
  private requestDurations: WindowEntry[] = [];

  // Cooldown to avoid alert spam (1 alert per type per minute)
  private lastErrorRateAlert: number = 0;
  private lastP99Alert: number = 0;
  private readonly alertCooldownMs: number = 60 * 1000; // 1 minute

  constructor(
    private readonly loggerService: LoggerService,
    private readonly configService: ConfigService,
  ) {
    this.errorRateThreshold = parseFloat(
      configService.get<string>('ERROR_RATE_ALERT_THRESHOLD', '0.01'),
    );
    this.p99ThresholdMs = parseInt(
      configService.get<string>('P99_ALERT_THRESHOLD_MS', '2000'),
      10,
    );
  }

  /**
   * Record a request metric (called by the LoggingInterceptor).
   * This allows the alerting system to track both successful and failed requests.
   */
  recordRequest(duration: number, isError: boolean): void {
    this.requestDurations.push({
      timestamp: Date.now(),
      isError,
      duration,
    });
    this.pruneWindow();
  }

  /**
   * Record an error (called by AllExceptionsFilter on every error).
   * This ensures errors that bypass the interceptor (e.g., 404 route-not-found)
   * are still tracked for alerting purposes.
   */
  recordError(): void {
    this.requestDurations.push({
      timestamp: Date.now(),
      isError: true,
      duration: 0,
    });
    this.pruneWindow();
  }

  /**
   * Check alert conditions and trigger alerts if thresholds are exceeded.
   * Called on every error. Also validates p99 latency across all requests.
   */
  checkAlerts(statusCode?: number, route?: string): void {
    const now = Date.now();
    const windowEntries = this.requestDurations.filter(
      (e) => now - e.timestamp < this.windowMs,
    );

    if (windowEntries.length === 0) return;

    // ── Error rate alert ──────────────────────────────────────
    const errorCount = windowEntries.filter((e) => e.isError).length;
    const errorRate = errorCount / windowEntries.length;

    if (
      errorRate > this.errorRateThreshold &&
      now - this.lastErrorRateAlert > this.alertCooldownMs &&
      windowEntries.length >= 100 // Need a minimum sample size
    ) {
      this.lastErrorRateAlert = now;
      this.loggerService.logAlert('ERROR_RATE', 'Error rate exceeded threshold', {
        errorRate: errorRate.toFixed(4),
        threshold: this.errorRateThreshold,
        errorCount,
        totalRequests: windowEntries.length,
        windowMinutes: 5,
        statusCode,
        route,
      });
    }

    // ── P99 latency alert ─────────────────────────────────────
    const durations = windowEntries
      .filter((e) => e.duration > 0)
      .map((e) => e.duration)
      .sort((a, b) => a - b);

    if (durations.length >= 100) {
      const p99Index = Math.ceil(durations.length * 0.99) - 1;
      const p99 = durations[p99Index];

      if (
        p99 > this.p99ThresholdMs &&
        now - this.lastP99Alert > this.alertCooldownMs
      ) {
        this.lastP99Alert = now;
        this.loggerService.logAlert('P99_LATENCY', 'P99 latency exceeded threshold', {
          p99LatencyMs: p99,
          thresholdMs: this.p99ThresholdMs,
          totalRequests: durations.length,
          windowMinutes: 5,
          route,
        });
      }
    }
  }

  /**
   * Remove entries older than the sliding window.
   */
  private pruneWindow(): void {
    const cutoff = Date.now() - this.windowMs;
    this.requestDurations = this.requestDurations.filter(
      (e) => e.timestamp >= cutoff,
    );
  }
}
