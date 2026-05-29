import { ConfigService } from '@nestjs/config';
export declare class LoggerService {
    private readonly configService;
    private readonly winston;
    constructor(configService: ConfigService);
    log(message: string, context?: string): void;
    error(message: string, trace?: string, context?: string): void;
    warn(message: string, context?: string): void;
    debug(message: string, context?: string): void;
    verbose(message: string, context?: string): void;
    logRequest(req: {
        method: string;
        url: string;
        userId?: string;
        correlationId?: string;
    }, res: {
        statusCode: number;
    }, duration: number): void;
    logError(error: Error | unknown, context?: string): void;
    logAlert(alertType: string, message: string, meta?: Record<string, unknown>): void;
}
