import { SetMetadata } from '@nestjs/common';

export const TWO_FACTOR_EXEMPT_KEY = 'twoFactorExempt';

/**
 * TwoFactorExempt — Decorator that marks a route or controller as
 * exempt from the TwoFactorGuard check.
 *
 * Endpoints that handle the 2FA verification flow itself need this
 * exemption to avoid a chicken-and-egg problem (you can't verify 2FA
 * if you're required to have already verified 2FA to access the
 * verification endpoint).
 *
 * @example
 *   @TwoFactorExempt()
 *   @Post('2fa/login-verify')
 *   async loginVerify2FA() { ... }
 */
export const TwoFactorExempt = () => SetMetadata(TWO_FACTOR_EXEMPT_KEY, true);
