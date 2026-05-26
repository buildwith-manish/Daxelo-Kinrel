import { SetMetadata } from '@nestjs/common';

export const API_SCOPE_KEY = 'apiKeyScope';

/**
 * Decorator to specify the required API key scope for a route.
 * Used in conjunction with ApiKeyGuard.
 *
 * @example
 * @ApiKeyScope('families:read')
 * @Get('families')
 * async listFamilies() { ... }
 */
export const ApiKeyScope = (scope: string) => SetMetadata(API_SCOPE_KEY, scope);
