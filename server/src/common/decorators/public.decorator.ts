import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';

/**
 * Public — Decorator that marks a route or controller as public
 * (no JWT authentication required).
 *
 * Used together with the JwtAuthGuard when it is registered as a
 * global guard, so that endpoints like login/register can remain
 * accessible without a token.
 *
 * @example
 *   @Public()
 *   @Post('login')
 *   async login() { ... }
 */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
