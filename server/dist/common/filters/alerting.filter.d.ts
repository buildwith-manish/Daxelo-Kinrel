import { ExceptionFilter, ArgumentsHost } from '@nestjs/common';
import { AlertingService } from '../alerting/alerting.service';
export declare class AlertingFilter implements ExceptionFilter {
    private readonly alertingService;
    constructor(alertingService: AlertingService);
    catch(exception: unknown, host: ArgumentsHost): void;
}
