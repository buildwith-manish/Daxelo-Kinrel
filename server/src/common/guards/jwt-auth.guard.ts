import {
  Injectable,
  ExecutionContext,
  UnauthorizedException,
  Inject,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';
import { InjectRedis } from '@nestjs-modules/ioredis';
import Redis from 'ioredis';

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
 * Additionally checks Redis for password-change invalidation:
 * If `pwd_changed:{userId}` exists in Redis, the access token is
 * rejected — forcing the user to re-authenticate.
 */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(
    private reflector: Reflector,
    @InjectRedis() private readonly redis: Redis,
  ) {
    super();
  }

  async canActivate(context: ExecutionContext) {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    if (isPublic) {
      return true;
    }

    // Run Passport JWT validation first
    const canActivate = await (super.canActivate(context) as Promise<boolean>);
    if (!canActivate) return false;

    // Check if password was changed after this token was issued
    const request = context.switchToHttp().getRequest();
    const userId = request.user?.sub || request.user?.id;
    if (userId) {
      try {
        const pwdChanged = await this.redis.get(`pwd_changed:${userId}`);
        if (pwdChanged) {
          const tokenIat = request.user?.iat
            ? request.user.iat * 1000 // Convert JWT iat (seconds) to milliseconds
            : 0;
          const changedAt = parseInt(pwdChanged, 10);
          if (changedAt > tokenIat) {
            throw new UnauthorizedException(
              'Session invalidated — please log in again',
            );
          }
        }
      } catch (error) {
        // Re-throw UnauthorizedException from above
        if (error instanceof UnauthorizedException) throw error;
        // Redis unavailable — allow request through (fail-open for availability)
      }
    }

    return true;
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
