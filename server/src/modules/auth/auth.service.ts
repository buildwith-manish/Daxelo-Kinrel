import {
  Injectable,
  UnauthorizedException,
  ConflictException,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../../prisma/prisma.service';
import * as bcrypt from 'bcryptjs';
import * as crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import * as speakeasy from 'speakeasy';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  // ── Register ────────────────────────────────────────────────────

  async register(dto: { name: string; email: string; password: string }) {
    const existing = await this.prisma.user.findUnique({
      where: { email: dto.email.trim().toLowerCase() },
    });

    if (existing) {
      throw new ConflictException('An account with this email already exists');
    }

    const passwordHash = await bcrypt.hash(dto.password, 12);

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
  }

  // ── Login ───────────────────────────────────────────────────────

  async login(dto: { email: string; password: string }, userAgent?: string, ipAddress?: string) {
    const user = await this.prisma.user.findUnique({
      where: { email: dto.email.trim().toLowerCase() },
    });

    if (!user || !user.passwordHash) {
      throw new UnauthorizedException('Invalid email or password');
    }

    // Try bcrypt first, then legacy SHA-256 fallback
    let passwordValid = await bcrypt.compare(dto.password, user.passwordHash);

    if (!passwordValid && user.passwordHash.startsWith('sha256:')) {
      const legacyHash = user.passwordHash.replace('sha256:', '');
      const inputHash = this.hashSha256(dto.password);
      if (inputHash === legacyHash) {
        passwordValid = true;
        // Auto-upgrade to bcrypt
        const newHash = await bcrypt.hash(dto.password, 12);
        await this.prisma.user.update({
          where: { id: user.id },
          data: { passwordHash: newHash },
        });
      }
    }

    if (!passwordValid) {
      throw new UnauthorizedException('Invalid email or password');
    }



    // Check 2FA if enabled
    // (2FA code verification handled in a separate step after login returns a challenge)

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

  async logout(refreshToken: string) {
    if (refreshToken) {
      const stored = await this.prisma.refreshToken.findUnique({
        where: { token: refreshToken },
      });
      if (stored && !stored.revokedAt) {
        await this.prisma.refreshToken.update({
          where: { token: refreshToken },
          data: { revokedAt: new Date() },
        });
      }
    }
    return { success: true };
  }

  // ── Change Password ─────────────────────────────────────────────

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

    const passwordValid = await bcrypt.compare(
      dto.currentPassword,
      user.passwordHash,
    );
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

    return { message: 'Password changed successfully' };
  }

  // ── Get Current User ────────────────────────────────────────────

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

  async setup2FA(userId: string) {
    const secret = speakeasy.generateSecret({
      name: `Daxelo Kinrel`,
      length: 32,
    });

    await this.prisma.user.update({
      where: { id: userId },
      data: { twoFactorSecret: secret.base32 },
    });

    return {
      secret: secret.base32,
      qrCodeUrl: secret.otpauth_url,
    };
  }

  // ── 2FA Verify ──────────────────────────────────────────────────

  async verify2FA(userId: string, code: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user || !user.twoFactorSecret) {
      throw new BadRequestException(
        '2FA setup not initiated. Call setup first.',
      );
    }

    const verified = speakeasy.totp.verify({
      secret: user.twoFactorSecret,
      encoding: 'base32',
      token: code,
      window: 2,
    });

    if (!verified) {
      throw new UnauthorizedException('Invalid 2FA code');
    }

    await this.prisma.user.update({
      where: { id: userId },
      data: { twoFactorEnabled: true },
    });

    return { verified: true };
  }

  // ── 2FA Disable ─────────────────────────────────────────────────

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
