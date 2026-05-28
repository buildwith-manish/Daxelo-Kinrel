import {
  Injectable,
  ExecutionContext,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

/**
 * JwtAuthGuard — Extends Passport's AuthGuard('jwt').
 *
 * On every request the JWT strategy validates the Bearer token and
 * attaches the decoded payload to `req.user`.
 *
 * If the token is missing, malformed, or expired the guard throws
 * an UnauthorizedException with a clear message that the Flutter
 * app can display or use to trigger a refresh-token flow.
 */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  canActivate(context: ExecutionContext) {
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
