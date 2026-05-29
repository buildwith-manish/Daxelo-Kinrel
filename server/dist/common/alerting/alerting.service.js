"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AlertingService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const logger_service_1 = require("../logger/logger.service");
let AlertingService = class AlertingService {
    constructor(loggerService, configService) {
        this.loggerService = loggerService;
        this.configService = configService;
        this.windowMs = 5 * 60 * 1000;
        this.requestDurations = [];
        this.lastErrorRateAlert = 0;
        this.lastP99Alert = 0;
        this.alertCooldownMs = 60 * 1000;
        this.errorRateThreshold = parseFloat(configService.get('ERROR_RATE_ALERT_THRESHOLD', '0.01'));
        this.p99ThresholdMs = parseInt(configService.get('P99_ALERT_THRESHOLD_MS', '2000'), 10);
    }
    recordRequest(duration, isError) {
        this.requestDurations.push({
            timestamp: Date.now(),
            isError,
            duration,
        });
        this.pruneWindow();
    }
    recordError() {
        this.requestDurations.push({
            timestamp: Date.now(),
            isError: true,
            duration: 0,
        });
        this.pruneWindow();
    }
    checkAlerts(statusCode, route) {
        const now = Date.now();
        const windowEntries = this.requestDurations.filter((e) => now - e.timestamp < this.windowMs);
        if (windowEntries.length === 0)
            return;
        const errorCount = windowEntries.filter((e) => e.isError).length;
        const errorRate = errorCount / windowEntries.length;
        if (errorRate > this.errorRateThreshold &&
            now - this.lastErrorRateAlert > this.alertCooldownMs &&
            windowEntries.length >= 100) {
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
        const durations = windowEntries
            .filter((e) => e.duration > 0)
            .map((e) => e.duration)
            .sort((a, b) => a - b);
        if (durations.length >= 100) {
            const p99Index = Math.ceil(durations.length * 0.99) - 1;
            const p99 = durations[p99Index];
            if (p99 > this.p99ThresholdMs &&
                now - this.lastP99Alert > this.alertCooldownMs) {
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
    pruneWindow() {
        const cutoff = Date.now() - this.windowMs;
        this.requestDurations = this.requestDurations.filter((e) => e.timestamp >= cutoff);
    }
};
exports.AlertingService = AlertingService;
exports.AlertingService = AlertingService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [logger_service_1.LoggerService,
        config_1.ConfigService])
], AlertingService);
//# sourceMappingURL=alerting.service.js.map