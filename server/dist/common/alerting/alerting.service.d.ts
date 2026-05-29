import { ConfigService } from '@nestjs/config';
import { LoggerService } from '../logger/logger.service';
export declare class AlertingService {
    private readonly loggerService;
    private readonly configService;
    private readonly windowMs;
    private readonly errorRateThreshold;
    private readonly p99ThresholdMs;
    private requestDurations;
    private lastErrorRateAlert;
    private lastP99Alert;
    private readonly alertCooldownMs;
    constructor(loggerService: LoggerService, configService: ConfigService);
    recordRequest(duration: number, isError: boolean): void;
    recordError(): void;
    checkAlerts(statusCode?: number, route?: string): void;
    private pruneWindow;
}
