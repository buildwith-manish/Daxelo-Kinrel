import { NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { Observable } from 'rxjs';
import { LoggerService } from '../logger/logger.service';
import { AlertingService } from '../alerting/alerting.service';
export declare class LoggingInterceptor implements NestInterceptor {
    private readonly loggerService;
    private readonly alertingService?;
    constructor(loggerService: LoggerService, alertingService?: AlertingService | undefined);
    intercept(context: ExecutionContext, next: CallHandler): Observable<any>;
}
