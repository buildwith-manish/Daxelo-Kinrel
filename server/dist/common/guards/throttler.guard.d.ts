import { ExecutionContext } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
export declare class CustomThrottlerGuard extends ThrottlerGuard {
    protected shouldSkip(context: ExecutionContext): Promise<boolean>;
}
