import {
  Injectable,
  ConflictException,
  UnauthorizedException,
  NotFoundException,
  Logger,
  BadRequestException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '@/common/prisma/prisma.service';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';
import { ChangePasswordDto } from './dto/change-password.dto';
import { Verify2FADto, Disable2FADto } from './dto/verify-2fa.dto';
import * as bcrypt from 'bcryptjs';
import * as crypto from 'crypto';
import * as speakeasy from 'speakeasy';
import { v4 as uuidv4 } from 'uuid';

// ── In-memory refresh token store ────────────────────────────────────
// In production, replace with a database-backed store (e.g. Redis or a
// RefreshToken Prisma model) for persistence across server restarts
// and horizontal scaling.
interface RefreshTokenEntry {
  userId: string;
  token: string;
  expiresAt: Date;
  revoked: boolean;
  familyId: string; // Token family for detecting token reuse
}

/**
 * AuthService — Handles all authentication logic for the DAXELO KINREL platform.
 *
 * Key features:
 * - bcrypt password hashing for new registrations
 * - Backward-compatible SHA-256 login for migrated users (auto-upgrades to bcrypt)
 * - JWT access (15min) + refresh (7d) token pair with rotation
 * - In-memory refresh token store with periodic cleanup
 * - Google OAuth user creation/lookup
 * - 2FA (TOTP) setup, verification, and disable
 * - Password change with current password verification
 */
@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);
  private readonly refreshTokens = new Map<string, RefreshTokenEntry>();

  /** bcrypt salt rounds for password hashing */
  private readonly BCRYPT_SALT_ROUNDS = 12;

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly config: ConfigService,
  ) {}

  // ═══════════════════════════════════════════════════════════════════
  // Registration
  // ═══════════════════════════════════════════════════════════════════

  /**
   * POST /api/auth/register
   * Register a new user with bcrypt password hashing.
   * Auto-creates a "My Family" and adds user as admin.
   */
  async register(dto: RegisterDto) {
    const { name, email, password } = dto;

    // Check if email already exists
    const existing = await this.prisma.user.findUnique({ where: { email } });
    if (existing) {
      throw new ConflictException('Email already registered');
    }

    // Hash password with bcryptjs
    const salt = await bcrypt.genSalt(this.BCRYPT_SALT_ROUNDS);
    const passwordHash = await bcrypt.hash(password, salt);

    // Create user + auto-create a default family in a transaction
    const result = await this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: { name, email, passwordHash },
        select: { id: true, email: true, name: true },
      });

      const family = await tx.family.create({
        data: {
          name: `${name}'s Family`,
          primaryLanguage: 'hi',
        },
      });

      // Add user as admin of their own family
      await tx.familyMember.create({
        data: {
          familyId: family.id,
          userId: user.id,
          role: 'admin',
        },
      });

      return { user, familyId: family.id };
    });

    this.logger.log(`User registered: ${email}`);

    return {
      user: result.user,
      familyId: result.familyId,
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  // Login
  // ═══════════════════════════════════════════════════════════════════

  /**
   * POST /api/auth/login
   * Login with email + password.
   * Supports both bcrypt (new) and SHA-256 (legacy) password hashes.
   * Legacy SHA-256 passwords are automatically upgraded to bcrypt on successful login.
   */
  async login(dto: LoginDto) {
    const { email, password } = dto;

    const user = await this.prisma.user.findUnique({
      where: { email },
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        preferredLanguage: true,
        passwordHash: true,
      },
    });

    if (!user || !user.passwordHash) {
      throw new UnauthorizedException('Invalid email or password');
    }

    // Try bcrypt verification first (new standard)
    const bcryptValid = await bcrypt.compare(password, user.passwordHash);

    if (bcryptValid) {
      // Modern bcrypt password — login succeeds
      const tokens = await this.generateTokenPair(user.id, user.email);

      this.logger.log(`User logged in: ${email}`);

      return {
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role,
          preferredLanguage: user.preferredLanguage,
        },
      };
    }

    // Try legacy SHA-256 verification (backward compat with original Next.js app)
    const sha256Hash = this.hashSha256(password);
    if (sha256Hash === user.passwordHash) {
      // Legacy SHA-256 password matched — auto-upgrade to bcrypt
      this.logger.warn(
        `Upgrading legacy SHA-256 password to bcrypt for: ${email}`,
      );

      const salt = await bcrypt.genSalt(this.BCRYPT_SALT_ROUNDS);
      const newHash = await bcrypt.hash(password, salt);

      await this.prisma.user.update({
        where: { id: user.id },
        data: { passwordHash: newHash },
      });

      const tokens = await this.generateTokenPair(user.id, user.email);

      this.logger.log(`User logged in (password upgraded): ${email}`);

      return {
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role,
          preferredLanguage: user.preferredLanguage,
        },
      };
    }

    // Neither bcrypt nor SHA-256 matched
    throw new UnauthorizedException('Invalid email or password');
  }

  // ═══════════════════════════════════════════════════════════════════
  // Change Password
  // ═══════════════════════════════════════════════════════════════════

  /**
   * POST /api/auth/change-password
   * Change password for an authenticated user.
   * Verifies the current password, then updates to the new bcrypt-hashed password.
   */
  async changePassword(userId: string, dto: ChangePasswordDto) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, passwordHash: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    if (!user.passwordHash) {
      throw new BadRequestException(
        'No password set for this account. Please set a password first.',
      );
    }

    // Verify current password
    const isValid = await bcrypt.compare(dto.currentPassword, user.passwordHash);
    if (!isValid) {
      // Also try legacy SHA-256
      const sha256Hash = this.hashSha256(dto.currentPassword);
      if (sha256Hash !== user.passwordHash) {
        throw new UnauthorizedException('Current password is incorrect');
      }
    }

    // Hash new password
    const salt = await bcrypt.genSalt(this.BCRYPT_SALT_ROUNDS);
    const newHash = await bcrypt.hash(dto.newPassword, salt);

    // Update password
    await this.prisma.user.update({
      where: { id: userId },
      data: { passwordHash: newHash },
    });

    // Revoke all refresh tokens to force re-login on other devices
    await this.revokeAllUserTokens(userId);

    this.logger.log(`Password changed for user: ${userId}`);

    return { message: 'Password changed successfully' };
  }

  // ═══════════════════════════════════════════════════════════════════
  // Two-Factor Authentication (2FA)
  // ═══════════════════════════════════════════════════════════════════

  /**
   * POST /api/auth/2fa/setup
   * Generate a TOTP secret and QR code URL for 2FA setup.
   * The secret is stored on the user record but 2FA is NOT enabled until verified.
   */
  async setup2FA(userId: string) {
    // Check if 2FA is already enabled
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, email: true, twoFactorEnabled: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    if (user.twoFactorEnabled) {
      throw new BadRequestException('2FA is already enabled. Disable it first to set up again.');
    }

    const secret = speakeasy.generateSecret({
      name: `KINREL (${user.email})`,
      length: 20,
    });

    // Store secret temporarily (not yet enabled — user must verify first)
    await this.prisma.user.update({
      where: { id: userId },
      data: { twoFactorSecret: secret.base32 },
    });

    this.logger.log(`2FA setup initiated for user: ${userId}`);

    return {
      secret: secret.base32,
      qrCodeUrl: secret.otpauth_url,
    };
  }

  /**
   * POST /api/auth/2fa/verify
   * Verify a TOTP code to enable 2FA.
   * Once verified, 2FA is enabled on the user account.
   */
  async verify2FA(userId: string, dto: Verify2FADto) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, twoFactorSecret: true, twoFactorEnabled: true },
    });

    if (!user || !user.twoFactorSecret) {
      throw new BadRequestException('2FA not set up. Call /auth/2fa/setup first.');
    }

    if (user.twoFactorEnabled) {
      throw new BadRequestException('2FA is already enabled.');
    }

    const verified = speakeasy.totp.verify({
      secret: user.twoFactorSecret,
      encoding: 'base32',
      token: dto.code,
      window: 2,
    });

    if (!verified) {
      throw new UnauthorizedException('Invalid 2FA code. Please try again.');
    }

    // Enable 2FA
    await this.prisma.user.update({
      where: { id: userId },
      data: { twoFactorEnabled: true },
    });

    this.logger.log(`2FA enabled for user: ${userId}`);

    return { verified: true };
  }

  /**
   * DELETE /api/auth/2fa
   * Disable 2FA — requires the user's password for security.
   */
  async disable2FA(userId: string, dto: Disable2FADto) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, passwordHash: true, twoFactorEnabled: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    if (!user.twoFactorEnabled) {
      throw new BadRequestException('2FA is not enabled.');
    }

    // Verify password
    if (!user.passwordHash) {
      throw new BadRequestException(
        'No password set for this account. Cannot verify identity.',
      );
    }

    const isValid = await bcrypt.compare(dto.password, user.passwordHash);
    if (!isValid) {
      throw new UnauthorizedException('Password is incorrect');
    }

    // Disable 2FA and clear the secret
    await this.prisma.user.update({
      where: { id: userId },
      data: { twoFactorEnabled: false, twoFactorSecret: null },
    });

    this.logger.log(`2FA disabled for user: ${userId}`);

    return { disabled: true };
  }

  // ═══════════════════════════════════════════════════════════════════
  // Token Refresh
  // ═══════════════════════════════════════════════════════════════════

  /**
   * POST /api/auth/refresh
   * Refresh JWT token pair. Uses rotation — the old refresh token is revoked
   * and a new pair is issued.
   */
  async refresh(refreshToken: string) {
    if (!refreshToken) {
      throw new BadRequestException('Refresh token is required');
    }

    // Verify the refresh token JWT signature and expiration
    let payload: { sub: string; email: string; type: string };
    try {
      payload = await this.jwtService.verifyAsync(refreshToken, {
        secret: this.config.get<string>('JWT_REFRESH_SECRET'),
      });
    } catch {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }

    if (payload.type !== 'refresh') {
      throw new UnauthorizedException('Invalid token type');
    }

    // Check in-memory store
    const stored = this.refreshTokens.get(refreshToken);
    if (!stored) {
      // Token not found in store — could be a reused token after logout.
      // Check if any token in the same family was already used (replay detection)
      this.logger.warn(
        `Refresh token not found in store — possible replay attack for user: ${payload.sub}`,
      );
      throw new UnauthorizedException(
        'Refresh token has been revoked or already used',
      );
    }

    if (stored.revoked) {
      // Token was explicitly revoked — possible token reuse attack
      this.logger.warn(
        `Revoked refresh token reuse detected for user: ${stored.userId}`,
      );
      // Revoke all tokens in the same family for security
      this.revokeTokenFamily(stored.familyId);
      throw new UnauthorizedException(
        'Refresh token has been revoked. Please log in again.',
      );
    }

    if (stored.userId !== payload.sub) {
      throw new UnauthorizedException('Token user mismatch');
    }

    if (new Date() > stored.expiresAt) {
      this.refreshTokens.delete(refreshToken);
      throw new UnauthorizedException('Refresh token has expired');
    }

    // Revoke old refresh token (rotation)
    const oldFamilyId = stored.familyId;
    stored.revoked = true;
    this.refreshTokens.delete(refreshToken);

    // Issue new token pair (same family for replay detection)
    const tokens = await this.generateTokenPair(
      payload.sub,
      payload.email,
      oldFamilyId,
    );

    return {
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  // Logout
  // ═══════════════════════════════════════════════════════════════════

  /**
   * POST /api/auth/logout
   * Invalidate a refresh token. Idempotent — returns success even if
   * the token was not found.
   */
  async logout(refreshToken: string) {
    if (!refreshToken) {
      return { success: true };
    }

    const stored = this.refreshTokens.get(refreshToken);
    if (stored) {
      stored.revoked = true;
      this.refreshTokens.delete(refreshToken);
      this.logger.log(`User logged out: ${stored.userId}`);
    }

    // Idempotent — always return success
    return { success: true };
  }

  // ═══════════════════════════════════════════════════════════════════
  // Get Current User
  // ═══════════════════════════════════════════════════════════════════

  /**
   * GET /api/auth/me
   * Get current authenticated user profile. JWT protected.
   */
  async me(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        name: true,
        phone: true,
        preferredLanguage: true,
        role: true,
        avatarUrl: true,
        twoFactorEnabled: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    return { user };
  }

  // ═══════════════════════════════════════════════════════════════════
  // Google OAuth
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Validate or create a user from Google OAuth profile.
   * Called by the Google callback controller method.
   */
  async validateOAuthUser(googleProfile: {
    email: string;
    name?: string;
    googleId?: string;
  }) {
    const { email, name, googleId } = googleProfile;

    // Try to find existing user by email
    let user = await this.prisma.user.findUnique({
      where: { email },
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        preferredLanguage: true,
      },
    });

    if (!user) {
      // Create a new user (no password — OAuth-only)
      const result = await this.prisma.$transaction(async (tx) => {
        const newUser = await tx.user.create({
          data: {
            email,
            name: name ?? email.split('@')[0],
            passwordHash: null,
          },
          select: {
            id: true,
            email: true,
            name: true,
            role: true,
            preferredLanguage: true,
          },
        });

        // Auto-create default family
        const family = await tx.family.create({
          data: {
            name: `${newUser.name}'s Family`,
            primaryLanguage: 'hi',
          },
        });

        await tx.familyMember.create({
          data: {
            familyId: family.id,
            userId: newUser.id,
            role: 'admin',
          },
        });

        return newUser;
      });

      user = result;
      this.logger.log(`OAuth user created: ${email}`);
    }

    const tokens = await this.generateTokenPair(user.id, user.email);

    return {
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      user,
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  // JWT Strategy Support
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Validate user for JWT strategy.
   * Returns null if user not found (strategy will throw Unauthorized).
   */
  async validateUser(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        preferredLanguage: true,
      },
    });

    return user ?? null;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Private Helpers
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Generate a JWT access + refresh token pair.
   * @param userId - User ID (becomes JWT `sub`)
   * @param email - User email (included in JWT payload)
   * @param familyId - Optional token family ID for replay detection
   */
  private async generateTokenPair(
    userId: string,
    email: string,
    familyId?: string,
  ) {
    const accessSecret =
      this.config.get<string>('JWT_ACCESS_SECRET') ?? 'fallback-dev-secret';
    const refreshSecret =
      this.config.get<string>('JWT_REFRESH_SECRET') ??
      'fallback-dev-refresh-secret';
    const accessExpiration = this.config.get<string>(
      'JWT_ACCESS_EXPIRATION',
      '15m',
    );
    const refreshExpiration = this.config.get<string>(
      'JWT_REFRESH_EXPIRATION',
      '7d',
    );

    const accessToken = await this.jwtService.signAsync(
      { sub: userId, email, type: 'access' },
      { secret: accessSecret, expiresIn: accessExpiration as any },
    );

    const refreshToken = await this.jwtService.signAsync(
      { sub: userId, email, type: 'refresh' },
      { secret: refreshSecret, expiresIn: refreshExpiration as any },
    );

    // Store refresh token in-memory map
    const tokenFamilyId = familyId ?? uuidv4();
    const expiresInMs = this.parseDuration(refreshExpiration);
    const expiresAt = new Date(Date.now() + expiresInMs);

    this.refreshTokens.set(refreshToken, {
      userId,
      token: refreshToken,
      expiresAt,
      revoked: false,
      familyId: tokenFamilyId,
    });

    return { accessToken, refreshToken };
  }

  /**
   * Revoke all refresh tokens belonging to a token family.
   * Used when replay attacks are detected.
   */
  private revokeTokenFamily(familyId: string) {
    let revoked = 0;
    for (const [token, entry] of this.refreshTokens.entries()) {
      if (entry.familyId === familyId) {
        entry.revoked = true;
        this.refreshTokens.delete(token);
        revoked++;
      }
    }
    if (revoked > 0) {
      this.logger.warn(
        `Revoked ${revoked} tokens in family ${familyId} (replay detection)`,
      );
    }
  }

  /**
   * Hash a password using SHA-256 (legacy — used only for backward
   * compatibility with the original Next.js CryptoJS-based hashing).
   */
  private hashSha256(password: string): string {
    return crypto.createHash('sha256').update(password).digest('hex');
  }

  /**
   * Parse a duration string like "15m", "7d", "30s" into milliseconds.
   */
  private parseDuration(duration: string): number {
    const match = duration.match(/^(\d+)(s|m|h|d)$/);
    if (!match) {
      this.logger.warn(
        `Could not parse duration "${duration}", defaulting to 7d`,
      );
      return 7 * 24 * 60 * 60 * 1000;
    }

    const value = parseInt(match[1], 10);
    const unit = match[2];

    const multipliers: Record<string, number> = {
      s: 1000,
      m: 60 * 1000,
      h: 60 * 60 * 1000,
      d: 24 * 60 * 60 * 1000,
    };

    return value * (multipliers[unit] ?? 7 * 24 * 60 * 60 * 1000);
  }

  /**
   * Periodic cleanup of expired refresh tokens.
   * Called from AuthModule's OnModuleInit lifecycle hook.
   */
  cleanupExpiredTokens() {
    const now = new Date();
    let cleaned = 0;
    for (const [token, entry] of this.refreshTokens.entries()) {
      if (entry.expiresAt < now || entry.revoked) {
        this.refreshTokens.delete(token);
        cleaned++;
      }
    }
    if (cleaned > 0) {
      this.logger.log(`Cleaned up ${cleaned} expired refresh tokens`);
    }
  }

  /**
   * Revoke all refresh tokens for a given user.
   * Useful when a user changes password or deletes their account.
   */
  async revokeAllUserTokens(userId: string) {
    let revoked = 0;
    for (const [token, entry] of this.refreshTokens.entries()) {
      if (entry.userId === userId) {
        entry.revoked = true;
        this.refreshTokens.delete(token);
        revoked++;
      }
    }
    if (revoked > 0) {
      this.logger.log(
        `Revoked ${revoked} refresh tokens for user: ${userId}`,
      );
    }
  }
}
