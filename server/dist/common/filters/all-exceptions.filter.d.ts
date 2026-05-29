import { ExceptionFilter, ArgumentsHost } from '@nestjs/common';
import { AlertingService } from '../alerting/alerting.service';
export declare class AllExceptionsFilter implements ExceptionFilter {
    private readonly alertingService?;
    private readonly logger;
    constructor(alertingService?: AlertingService | undefined);
    catch(exception: unknown, host: ArgumentsHost): void;
}
