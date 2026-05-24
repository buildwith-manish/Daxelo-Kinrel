import { SetMetadata } from '@nestjs/common';

export const ROLES_KEY = 'roles';

/**
 * Decorator that sets required roles for a route or controller.
 * @example @Roles('admin', 'agent')
 */
export const Roles = (...roles: string[]) => SetMetadata(ROLES_KEY, roles);
