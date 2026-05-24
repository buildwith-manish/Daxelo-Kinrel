import { SetMetadata } from '@nestjs/common';

export const SCOPES_KEY = 'scopes';

/**
 * Decorator that sets required API key scopes for a route or controller.
 * @example @Scopes('families:read', 'persons:read')
 */
export const Scopes = (...scopes: string[]) => SetMetadata(SCOPES_KEY, scopes);
