import { createParamDecorator, ExecutionContext } from '@nestjs/common';

/**
 * CurrentUser — Parameter decorator that extracts the authenticated user
 * from the request object attached by the JwtAuthGuard.
 *
 * Usage:
 *   @CurrentUser()          user: any      → full user payload
 *   @CurrentUser('id')      userId: string → specific field
 *   @CurrentUser('email')   email: string  → specific field
 *   @CurrentUser('role')    role: string   → specific field
 */
export const CurrentUser = createParamDecorator(
  (data: string | undefined, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest();
    const user = request.user;

    // If a specific field is requested, return just that field
    if (data) {
      return user?.[data];
    }

    // Otherwise return the full user object
    return user;
  },
);
