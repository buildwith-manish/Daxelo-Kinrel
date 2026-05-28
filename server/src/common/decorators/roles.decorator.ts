import { SetMetadata } from '@nestjs/common';

export const ROLES_KEY = 'roles';

/**
 * Roles — Decorator that sets required roles for a route or controller.
 *
 * Used together with the RolesGuard to enforce role-based access control.
 *
 * @example
 *   @Roles('admin')                          // single role
 *   @Roles('admin', 'agent')                 // multiple roles (any match)
 *   @Controller('admin')
 *   @Roles('admin')                          // applies to all routes in controller
 */
export const Roles = (...roles: string[]) => SetMetadata(ROLES_KEY, roles);
