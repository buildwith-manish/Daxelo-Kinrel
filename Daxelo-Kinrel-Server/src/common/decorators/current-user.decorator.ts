import { createParamDecorator, ExecutionContext } from '@nestjs/common';

/**
 * Decorator that extracts the authenticated user from the request object.
 * Optionally accepts a property name to extract a specific field.
 *
 * @example
 * @CurrentUser() user: any
 * @CurrentUser('id') userId: string
 */
export const CurrentUser = createParamDecorator(
  (data: string | undefined, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest();
    const user = request.user;

    if (data) {
      return user?.[data];
    }

    return user;
  },
);
