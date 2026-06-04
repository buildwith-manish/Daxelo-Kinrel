import { Injectable, ExecutionContext } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';

/**
 * Custom ThrottlerGuard that exempts certain routes from rate limiting.
 * Exempted: /api/sync, /api/health, Socket.io endpoints
 */
@Injectable()
export class CustomThrottlerGuard extends ThrottlerGuard {
  protected async shouldSkip(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const url: string = request.url || '';

    // Exempt health check, sync, and Socket.io endpoints
    if (
      url.includes('/health') ||
      url.includes('/sync') ||
      url.startsWith('/socket.io')
    ) {
      return true;
    }

    return super.shouldSkip(context);
  }
}
