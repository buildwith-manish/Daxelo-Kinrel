import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { TWO_FACTOR_EXEMPT_KEY } from '../decorators/two-factor-exempt.decorator';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';
import { TwoFactorVerificationService } from '../services/two-factor-verification.service';

/**
 * TwoFactorGuard — Enforces two-factor authentication for authenticated users.
 *
 * This guard runs AFTER JwtAuthGuard (both are registered as global guards).
 * By the time this guard executes, `req.user` is populated with the
 * authenticated user payload.
 *
 * Logic:
 * 1. If the route is marked @Public() → allow (no auth required at all)
 * 2. If the route is marked @TwoFactorExempt() → allow (2FA check skipped)
 * 3. If req.user is not set (e.g. unauthenticated request to a non-public
 *    route that hasn't been caught by JwtAuthGuard) → allow (JwtAuthGuard
 *    will handle the 401 separately)
 * 4. If user.twoFactorEnabled is false → allow (2FA not configured)
 * 5. If user has recently verified 2FA (per TwoFactorVerificationService) → allow
 * 6. Otherwise → 403 "Two-factor authentication required"
 */
@Injectable()
export class TwoFactorGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly twoFactorVerificationService: TwoFactorVerificationService,
  ) {}

  canActivate(context: ExecutionContext): boolean {
    // ── Check @Public() decorator ────────────────────────────────
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) {
      return true;
    }

    // ── Check @TwoFactorExempt() decorator ───────────────────────
    const isExempt = this.reflector.getAllAndOverride<boolean>(
      TWO_FACTOR_EXEMPT_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (isExempt) {
      return true;
    }

    // ── Get the authenticated user from the request ──────────────
    const request = context.switchToHttp().getRequest();
    const user = request.user;

    // If no user object, JwtAuthGuard hasn't authenticated the request.
    // Let the auth guard handle the 401 response.
    if (!user) {
      return true;
    }

    // ── Check if 2FA is enabled for this user ────────────────────
    if (!user.twoFactorEnabled) {
      return true;
    }

    // ── Check if user has recently verified 2FA ──────────────────
    if (this.twoFactorVerificationService.isVerified(user.id)) {
      return true;
    }

    // ── 2FA required but not yet verified ────────────────────────
    throw new ForbiddenException('Two-factor authentication required');
  }
}
