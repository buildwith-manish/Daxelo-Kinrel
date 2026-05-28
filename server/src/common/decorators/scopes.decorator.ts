import { SetMetadata } from '@nestjs/common';

export const SCOPES_KEY = 'scopes';

/**
 * Scopes — Decorator that sets required API key scopes for a route or controller.
 *
 * Used together with the ApiKeyGuard to enforce scope-based access control
 * for third-party developer API keys.
 *
 * @example
 *   @Scopes('families:read')                         // single scope
 *   @Scopes('families:read', 'persons:read')          // multiple scopes
 *   @Controller('developer')
 *   @Scopes('developer:admin')                        // applies to all routes
 */
export const Scopes = (...scopes: string[]) =>
  SetMetadata(SCOPES_KEY, scopes);
