import {
  Injectable,
  UnauthorizedException,
  ConflictException,
  BadRequestException,
  NotFoundException,
  InternalServerErrorException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../../prisma/prisma.service';
import { TwoFactorVerificationService } from '../../common/services/two-factor-verification.service';
import Redis from 'ioredis';
import * as bcrypt from 'bcryptjs';
import * as crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { authenticator } from '@otplib/preset-default';
import { encrypt, decrypt } from '../../common/utils/encryption.util';
import { Cron, CronExpression } from '@nestjs/schedule';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

@Injectable()
export class AuthService {
  private redis: Redis | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly twoFactorVerificationService: TwoFactorVerificationService,
  ) {
    const redisUrl = this.config.get<string>('REDIS_URL', '');
    if (redisUrl && redisUrl !== 'redis://localhost:6379') {
      this.redis = new Redis(redisUrl, {
        lazyConnect: true,
        maxRetriesPerRequest: 1,
        connectTimeout: 5000,
      });

      this.redis.on('error', (err) => {
        if (err.message?.includes('ECONNREFUSED') || err.message?.includes('AggregateError')) {
          if (this.redis) {
            this.redis.disconnect();
            this.redis = null;
          }
        }
      });

      this.redis.connect().catch(() => {
        this.redis = null;
      });
    }
  }

  // ── Register ────────────────────────────────────────────────────

  /** Registers a new user and auto-creates their first family. */
  async register(dto: { name: string; email: string; password: string }) {
    const existing = await this.prisma.user.findUnique({
      where: { email: dto.email.trim().toLowerCase() },
    });

    if (existing) {
      throw new ConflictException('An account with this email already exists');
    }

    const passwordHash = await bcrypt.hash(dto.password, 12);

    try {
    const result = await this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          email: dto.email.trim().toLowerCase(),
          name: dto.name.trim(),
          passwordHash,
          role: 'user',
          preferredLanguage: 'en',
        },
        select: { id: true, email: true, name: true },
      });

      // Auto-create "My Family" for the new user
      const family = await tx.family.create({
        data: {
          name: 'My Family',
          createdBy: user.id,
          primaryLanguage: 'en',
          privacyMode: 'private',
          memberCount: 1,
          lastActivityAt: new Date(),
        },
      });

      await tx.familyMember.create({
        data: {
          familyId: family.id,
          userId: user.id,
          role: 'admin',
        },
      });

      return { user, familyId: family.id };
    });

    return result;
    } catch (error: any) {
      // Handle race condition: two concurrent registrations with the same email
      // both pass the findUnique check before either creates the user
      if (error?.code === 'P2002' && error?.meta?.target?.includes('email')) {
        throw new ConflictException('An account with this email already exists');
      }
      throw error;
    }
  }

  // ── Login ───────────────────────────────────────────────────────

  /** Authenticates a user and returns tokens, or a 2FA challenge if enabled. */
  async login(dto: { email: string; password: string }, userAgent?: string, ipAddress?: string) {
    const user = await this.prisma.user.findUnique({
      where: { email: dto.email.trim().toLowerCase() },
    });

    if (!user || !user.passwordHash) {
      throw new UnauthorizedException('Invalid email or password');
    }

    const passwordValid = await this.verifyPasswordWithLegacyUpgrade(user.id, dto.password, user.passwordHash);

    if (!passwordValid) {
      throw new UnauthorizedException('Invalid email or password');
    }

    // Check 2FA if enabled — issue challenge token instead of real tokens
    if (user.twoFactorEnabled) {
      const challengeToken = this.jwt.sign(
        { sub: user.id, scope: '2fa_challenge' },
        {
          secret: this.config.get<string>('JWT_ACCESS_SECRET'),
          expiresIn: '5m',
        },
      );
      return {
        requiresTwoFactor: true,
        challengeToken,
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role,
          preferredLanguage: user.preferredLanguage,
        },
      };
    }

    const tokens = await this.generateTokenPair(
      user.id,
      user.email,
      user.role,
      undefined,
      userAgent,
      ipAddress,
    );

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

  // ── Refresh ─────────────────────────────────────────────────────

  /** Rotates a refresh token and returns a new token pair within the same family. */
  async refresh(oldRefreshToken: string): Promise<TokenPair> {
    const stored = await this.prisma.refreshToken.findUnique({
      where: { token: oldRefreshToken },
      include: { user: true },
    });

    if (!stored) {
      throw new UnauthorizedException('Invalid refresh token');
    }

    if (stored.expiresAt < new Date()) {
      await this.prisma.refreshToken.delete({
        where: { token: oldRefreshToken },
      });
      throw new UnauthorizedException('Refresh token has expired');
    }

    if (stored.revokedAt) {
      // Token reuse detected — revoke all tokens in the same family
      await this.revokeTokenFamily(stored.familyId);
      throw new UnauthorizedException(
        'Refresh token reuse detected. All sessions have been revoked.',
      );
    }

    // Rotate: mark old token as revoked
    await this.prisma.refreshToken.update({
      where: { token: oldRefreshToken },
      data: { revokedAt: new Date() },
    });

    // Generate new pair in the same family
    const newTokens = await this.generateTokenPair(
      stored.user.id,
      stored.user.email,
      stored.user.role,
      stored.familyId, // Keep same family for rotation tracking
    );

    return newTokens;
  }

  // ── Logout ──────────────────────────────────────────────────────

  /** Revokes the given refresh token and clears 2FA verification status. */
  async logout(refreshToken: string) {
    let userId: string | null = null;
    if (refreshToken) {
      const stored = await this.prisma.refreshToken.findUnique({
        where: { token: refreshToken },
      });
      if (stored) {
        userId = stored.userId;
        if (!stored.revokedAt) {
          await this.prisma.refreshToken.update({
            where: { token: refreshToken },
            data: { revokedAt: new Date() },
          });
        }
      }
    }
    // Clear 2FA verification status so next login requires fresh verification
    if (userId) {
      await this.twoFactorVerificationService.clearVerification(userId);
    }
    return { success: true };
  }

  // ── Change Password ─────────────────────────────────────────────

  /** Changes the user's password and revokes all active sessions. */
  async changePassword(
    userId: string,
    dto: { currentPassword: string; newPassword: string },
  ) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user || !user.passwordHash) {
      throw new NotFoundException('User not found');
    }

    const passwordValid = await this.verifyPasswordWithLegacyUpgrade(userId, dto.currentPassword, user.passwordHash);

    if (!passwordValid) {
      throw new UnauthorizedException('Current password is incorrect');
    }

    const newHash = await bcrypt.hash(dto.newPassword, 12);

    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: userId },
        data: { passwordHash: newHash },
      });
      // Revoke all refresh tokens (force re-login)
      await tx.refreshToken.updateMany({
        where: { userId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
    });

    // Invalidate active access tokens by marking password change in Redis
    // JwtAuthGuard checks this key — if set, the access token is rejected
    // TTL of 15 minutes matches maximum access token lifetime
    try {
      if (this.redis) {
        await this.redis.setex(`pwd_changed:${userId}`, 900, Date.now().toString());
      }
    } catch {
      // Redis unavailable — refresh tokens are already revoked,
      // so the user will need to re-login when their access token expires
    }

    return { message: 'Password changed successfully' };
  }

  // ── Get Current User ────────────────────────────────────────────

  /** Returns the currently authenticated user's profile. */
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
      },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    return { user };
  }

  // ── 2FA Setup ───────────────────────────────────────────────────

  /** Generates a TOTP secret and returns the QR code URL for 2FA setup. */
  async setup2FA(userId: string) {
    const secret = authenticator.generateSecret();

    const encryptionKey = this.config.get<string>('ENCRYPTION_KEY');
    if (!encryptionKey) {
      throw new InternalServerErrorException('ENCRYPTION_KEY is not configured — cannot process 2FA');
    }
    const encryptedSecret = encrypt(secret, encryptionKey);

    await this.prisma.user.update({
      where: { id: userId },
      data: { twoFactorSecret: encryptedSecret },
    });

    const qrCodeUrl = authenticator.keyuri('Daxelo Kinrel', 'Daxelo Kinrel', secret);
    return { secret, qrCodeUrl };
  }

  // ── 2FA Verify ──────────────────────────────────────────────────

  /** Verifies a TOTP code during 2FA setup and enables 2FA on success. */
  async verify2FA(userId: string, code: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user || !user.twoFactorSecret) {
      throw new BadRequestException(
        '2FA setup not initiated. Call setup first.',
      );
    }

    // ── TOTP Replay Protection (BUG-04 fix) ────────────────────
    // Prevent the same TOTP code from being used more than once.
    // Without this, a captured code could be replayed within the time window.
    const usedKey = `totp_used:${userId}:${code}`;
    if (this.redis && await this.redis.exists(usedKey)) {
      throw new UnauthorizedException(
        'TOTP code already used. Please wait for the next code.',
      );
    }

    const encryptionKey = this.config.get<string>('ENCRYPTION_KEY');
    if (!encryptionKey) {
      throw new InternalServerErrorException('ENCRYPTION_KEY is not configured — cannot process 2FA');
    }
    const decryptedSecret = decrypt(user.twoFactorSecret, encryptionKey);

    const verified = authenticator.verify({ token: code, secret: decryptedSecret });

    if (!verified) {
      throw new UnauthorizedException('Invalid 2FA code');
    }

    // Mark this code as used — TTL matches the TOTP step window (60s covers 2 steps)
    if (this.redis) {
      await this.redis.setex(usedKey, 60, '1');
    }

    await this.prisma.user.update({
      where: { id: userId },
      data: { twoFactorEnabled: true },
    });

    return { verified: true };
  }

  // ── 2FA Login Verify ────────────────────────────────────────────

  /** Verifies a TOTP code during login and issues real tokens on success. */
  async loginVerify2FA(userId: string, code: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user) {
      throw new UnauthorizedException('User not found');
    }

    if (!user.twoFactorEnabled || !user.twoFactorSecret) {
      throw new BadRequestException(
        '2FA is not enabled for this account',
      );
    }

    // ── TOTP Replay Protection (BUG-04 fix) ────────────────────
    const usedKey = `totp_used:${userId}:${code}`;
    if (this.redis && await this.redis.exists(usedKey)) {
      throw new UnauthorizedException(
        'TOTP code already used. Please wait for the next code.',
      );
    }

    const encryptionKey = this.config.get<string>('ENCRYPTION_KEY');
    if (!encryptionKey) {
      throw new InternalServerErrorException('ENCRYPTION_KEY is not configured — cannot process 2FA');
    }
    const decryptedSecret = decrypt(user.twoFactorSecret, encryptionKey);

    const verified = authenticator.verify({ token: code, secret: decryptedSecret });

    if (!verified) {
      throw new UnauthorizedException('Invalid 2FA code');
    }

    // Mark this code as used — TTL matches the TOTP step window (60s covers 2 steps)
    if (this.redis) {
      await this.redis.setex(usedKey, 60, '1');
    }

    // Mark user as 2FA-verified so subsequent requests pass the TwoFactorGuard
    await this.twoFactorVerificationService.markVerified(user.id);

    // After successful 2FA verification, generate real tokens
    const tokens = await this.generateTokenPair(user.id, user.email, user.role);
    return {
      verified: true,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    };
  }

  // ── 2FA Disable ─────────────────────────────────────────────────

  /** Disables 2FA for the user after confirming their password. */
  async disable2FA(userId: string, password: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    const passwordValid = user.passwordHash
      ? await bcrypt.compare(password, user.passwordHash)
      : false;
    if (!passwordValid) {
      throw new UnauthorizedException('Password is incorrect');
    }

    await this.prisma.user.update({
      where: { id: userId },
      data: {
        twoFactorEnabled: false,
        twoFactorSecret: null,
      },
    });

    return { disabled: true };
  }

  // ── Validate User (for JWT Strategy) ────────────────────────────

  /** Validates a JWT payload and returns the user record, or null. */
  async validateUser(payload: { sub: string; email: string }) {
    const user = await this.prisma.user.findUnique({
      where: { id: payload.sub },
      select: {
        id: true,
        email: true,
        name: true,
        username: true,
        role: true,
        avatarUrl: true,
        preferredLanguage: true,
        twoFactorEnabled: true,
      },
    });

    if (!user) {
      return null;
    }

    return user;
  }

  // ── Token Generation ────────────────────────────────────────────

  /** Generates an access/refresh token pair and persists the refresh token. */
  async generateTokenPair(
    userId: string,
    email: string,
    role: string,
    existingFamilyId?: string,
    userAgent?: string,
    ipAddress?: string,
  ): Promise<TokenPair> {
    const accessToken = this.jwt.sign(
      { sub: userId, email, role, type: 'access' },
      {
        secret: this.config.get<string>('JWT_ACCESS_SECRET'),
        expiresIn: this.config.get<string>('JWT_ACCESS_EXPIRATION', '15m') as any,
      },
    );

    const refreshToken = uuidv4();
    const familyId = existingFamilyId || uuidv4();
    const refreshExpiration = this.config.get<string>(
      'JWT_REFRESH_EXPIRATION',
      '7d',
    );
    const expiresAt = this.computeExpiryDate(refreshExpiration);

    await this.prisma.refreshToken.create({
      data: {
        token: refreshToken,
        userId,
        familyId,
        expiresAt,
        userAgent: userAgent || null,
        ipAddress: ipAddress || null,
      },
    });

    return { accessToken, refreshToken };
  }

  // ── Private Helpers ─────────────────────────────────────────────

  private async verifyPasswordWithLegacyUpgrade(
    userId: string,
    inputPassword: string,
    storedHash: string,
  ): Promise<boolean> {
    let valid = await bcrypt.compare(inputPassword, storedHash);
    if (!valid && storedHash.startsWith('sha256:')) {
      const legacyHash = storedHash.replace('sha256:', '');
      if (this.hashSha256(inputPassword) === legacyHash) {
        valid = true;
        // Auto-upgrade to bcrypt
        const newHash = await bcrypt.hash(inputPassword, 12);
        await this.prisma.user.update({
          where: { id: userId },
          data: { passwordHash: newHash },
        });
      }
    }
    return valid;
  }

  private hashSha256(password: string): string {
    return crypto.createHash('sha256').update(password).digest('hex');
  }

  private computeExpiryDate(duration: string): Date {
    const now = new Date();
    const match = duration.match(/^(\d+)([smhd])$/);
    if (!match) return new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

    const value = parseInt(match[1], 10);
    const unit = match[2];
    const multipliers: Record<string, number> = {
      s: 1000,
      m: 60000,
      h: 3600000,
      d: 86400000,
    };
    return new Date(now.getTime() + value * (multipliers[unit] || 86400000));
  }

  private async revokeTokenFamily(familyId: string) {
    await this.prisma.refreshToken.updateMany({
      where: { familyId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  // ── Session Management ────────────────────────────────────────────

  /**
   * Get all active sessions for a user (from RefreshToken records).
   * Each refresh token represents a session.
   */
  async getUserSessions(userId: string, currentRefreshToken?: string) {
    const tokens = await this.prisma.refreshToken.findMany({
      where: {
        userId,
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: 'desc' },
    });

    let currentTokenFamily: string | null = null;
    if (currentRefreshToken) {
      const currentToken = await this.prisma.refreshToken.findUnique({
        where: { token: currentRefreshToken },
        select: { familyId: true },
      });
      currentTokenFamily = currentToken?.familyId || null;
    }

    return tokens.map((token) => {
      const ua = token.userAgent || '';
      const parsed = this.parseUserAgent(ua);

      return {
        id: token.id,
        deviceName: parsed.deviceName,
        deviceType: parsed.deviceType,
        location: token.ipAddress || null,
        lastActiveAt: token.createdAt,
        isCurrentDevice: token.familyId === currentTokenFamily,
      };
    });
  }

  /**
   * Revoke a specific session by its ID (RefreshToken ID).
   */
  async revokeSession(sessionId: string, userId: string) {
    const token = await this.prisma.refreshToken.findFirst({
      where: { id: sessionId, userId },
    });

    if (!token) {
      throw new NotFoundException('Session not found');
    }

    await this.prisma.refreshToken.update({
      where: { id: sessionId },
      data: { revokedAt: new Date() },
    });

    return { success: true, message: 'Session revoked' };
  }

  /**
   * Revoke all sessions except the current one.
   */
  async revokeAllSessionsExceptCurrent(userId: string, currentRefreshToken?: string) {
    let currentTokenFamily: string | null = null;
    if (currentRefreshToken) {
      const currentToken = await this.prisma.refreshToken.findUnique({
        where: { token: currentRefreshToken },
        select: { familyId: true },
      });
      currentTokenFamily = currentToken?.familyId || null;
    }

    const whereClause: any = {
      userId,
      revokedAt: null,
    };

    if (currentTokenFamily) {
      whereClause.familyId = { not: currentTokenFamily };
    }

    const result = await this.prisma.refreshToken.updateMany({
      where: whereClause,
      data: { revokedAt: new Date() },
    });

    return {
      success: true,
      message: `${result.count} session(s) revoked`,
      revokedCount: result.count,
    };
  }

  /**
   * Parse a User-Agent string into device name and type.
   */
  private parseUserAgent(ua: string): { deviceName: string; deviceType: string } {
    if (!ua) {
      return { deviceName: 'Unknown Device', deviceType: 'unknown' };
    }

    let deviceName = 'Unknown Device';
    let deviceType = 'unknown';

    // Detect platform
    if (/iPhone/i.test(ua)) {
      deviceType = 'mobile';
      deviceName = 'iPhone';
    } else if (/iPad/i.test(ua)) {
      deviceType = 'tablet';
      deviceName = 'iPad';
    } else if (/Android/i.test(ua)) {
      deviceType = /Mobile/i.test(ua) ? 'mobile' : 'tablet';
      deviceName = /Mobile/i.test(ua) ? 'Android Phone' : 'Android Tablet';
    } else if (/Windows/i.test(ua)) {
      deviceType = 'desktop';
      deviceName = 'Windows PC';
    } else if (/Macintosh/i.test(ua)) {
      deviceType = 'desktop';
      deviceName = 'Mac';
    } else if (/Linux/i.test(ua)) {
      deviceType = 'desktop';
      deviceName = 'Linux PC';
    }

    // Try to get browser name
    let browser = '';
    if (/Edg\//i.test(ua)) {
      browser = 'Edge';
    } else if (/Chrome/i.test(ua) && !/Edg/i.test(ua)) {
      browser = 'Chrome';
    } else if (/Firefox/i.test(ua)) {
      browser = 'Firefox';
    } else if (/Safari/i.test(ua) && !/Chrome/i.test(ua)) {
      browser = 'Safari';
    }

    // Try to detect Flutter/Dart app
    if (/Dart/i.test(ua)) {
      deviceType = /Mobile|iPhone|Android/i.test(ua) ? 'mobile' : deviceType;
      browser = 'Daxelo App';
    }

    if (browser && deviceName !== 'Unknown Device') {
      deviceName = `${deviceName} — ${browser}`;
    } else if (browser) {
      deviceName = browser;
    }

    return { deviceName, deviceType };
  }

  /**
   * Cleanup expired and old revoked tokens.
   * Should be called periodically (e.g., via interval in module init).
   */
  @Cron(CronExpression.EVERY_DAY_AT_MIDNIGHT)
  async cleanupExpiredTokens() {
    const thirtyDaysAgo = new Date(
      Date.now() - 30 * 24 * 60 * 60 * 1000,
    );

    const result = await this.prisma.refreshToken.deleteMany({
      where: {
        OR: [
          { expiresAt: { lt: new Date() } },
          {
            revokedAt: { not: null, lt: thirtyDaysAgo },
          },
        ],
      },
    });

    return { deleted: result.count };
  }
}
