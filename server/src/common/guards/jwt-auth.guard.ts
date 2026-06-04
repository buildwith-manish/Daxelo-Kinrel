import {
  Injectable,
  ExecutionContext,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';

/**
 * JwtAuthGuard — Extends Passport's AuthGuard('jwt').
 *
 * Supports the @Public() decorator: when a route or controller is
 * marked with @Public(), the guard allows the request through
 * without a valid JWT token.
 *
 * On every non-public request the JWT strategy validates the Bearer
 * token and attaches the decoded payload to `req.user`.
 *
 * If the token is missing, malformed, or expired the guard throws
 * an UnauthorizedException with a clear message that the Flutter
 * app can display or use to trigger a refresh-token flow.
 */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private reflector: Reflector) {
    super();
  }

  canActivate(context: ExecutionContext) {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    if (isPublic) {
      return true;
    }

    return super.canActivate(context);
  }

  handleRequest<TUser = any>(err: any, user: TUser, info: any): TUser {
    if (err || !user) {
      const reason =
        info?.message === 'jwt expired'
          ? 'Access token has expired — please refresh'
          : info?.message === 'jwt malformed'
            ? 'Access token is malformed'
            : 'Invalid or expired authentication token';

      throw err || new UnauthorizedException(reason);
    }
    return user;
  }
}
