import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ROLES_KEY } from '../decorators/roles.decorator';

interface AuthenticatedRequest extends Request {
  user?: {
    id: string;
    email: string;
    role: string;
    [key: string]: any;
  };
}

/**
 * RolesGuard — Checks the @Roles() decorator against user.role.
 *
 * Behaviour:
 *  - If no @Roles() decorator is present on the handler or class,
 *    the route is accessible to any authenticated user (guard passes).
 *  - If @Roles('admin', 'agent') is set, user.role must be one of
 *    the listed values.
 *  - If the user has no role or an insufficient role a
 *    ForbiddenException (403) is thrown.
 */
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<string[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    // No @Roles() decorator → allow access
    if (!requiredRoles || requiredRoles.length === 0) {
      return true;
    }

    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const user = request.user;

    if (!user) {
      throw new ForbiddenException('Authentication required');
    }

    const hasRole = requiredRoles.includes(user.role);
    if (!hasRole) {
      throw new ForbiddenException(
        `Insufficient role. Required: ${requiredRoles.join(', ')}. Got: ${user.role}`,
      );
    }

    return true;
  }
}
