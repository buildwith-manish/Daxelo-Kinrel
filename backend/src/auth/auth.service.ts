import { Injectable, UnauthorizedException, ConflictException, BadRequestException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma/prisma.service';
import * as CryptoJS from 'crypto-js';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';

@Injectable()
export class AuthService {
  constructor(
    private prisma: PrismaService,
    private jwtService: JwtService,
  ) {}

  /**
   * Register a new user
   * Matches: POST /api/auth/register
   * - SHA-256 password hash (CryptoJS) — same as current Next.js
   * - Auto-create default family
   * - Return { user: { id, email, name }, familyId }
   */
  async register(dto: RegisterDto) {
    const { name, email, password, referralCode } = dto;

    // Check existing user
    const existing = await this.prisma.user.findUnique({ where: { email } });
    if (existing) {
      throw new ConflictException('Email already registered');
    }

    // SHA-256 hash — same as current Next.js backend
    const passwordHash = CryptoJS.SHA256(password).toString();

    // Create user
    const user = await this.prisma.user.create({
      data: { name, email, passwordHash },
      select: { id: true, email: true, name: true },
    });

    // Auto-create default family
    const family = await this.prisma.family.create({
      data: {
        name: `${name}'s Family`,
        primaryLanguage: 'hi',
      },
    });

    // Add user as admin
    await this.prisma.familyMember.create({
      data: {
        familyId: family.id,
        userId: user.id,
        role: 'admin',
      },
    });

    // Handle referral code if provided
    if (referralCode) {
      try {
        const referrer = await this.prisma.user.findUnique({
          where: { referralCode },
          select: { id: true },
        });

        if (referrer && referrer.id !== user.id) {
          // Check if the new user hasn't already been referred
          const existingReferral = await this.prisma.referral.findFirst({
            where: { referredId: user.id },
          });

          if (!existingReferral) {
            await this.prisma.referral.create({
              data: {
                referrerId: referrer.id,
                referredId: user.id,
                code: referralCode,
                status: 'accepted',
                acceptedAt: new Date(),
              },
            });
          }
        }
      } catch (error) {
        // Log but don't fail registration if referral processing fails
        console.error('Failed to process referral code:', error instanceof Error ? error.message : String(error));
      }
    }

    // Generate tokens
    const accessToken = this.generateAccessToken({
      id: user.id,
      email: user.email,
      role: 'user',
      preferredLanguage: 'en',
    });
    const refreshToken = this.generateRefreshToken(user.id);

    // Store hashed refresh token in DB
    await this.storeRefreshToken(user.id, refreshToken);

    return {
      user,
      familyId: family.id,
      accessToken,
      refreshToken,
    };
  }

  /**
   * Login
   * Matches current NextAuth behavior
   * - Verify email + SHA-256 password
   * - Return user + tokens
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
        passwordHash: true,
        preferredLanguage: true,
      },
    });

    if (!user || !user.passwordHash) {
      throw new UnauthorizedException('Invalid email or password');
    }

    // Verify SHA-256 hash
    const hash = CryptoJS.SHA256(password).toString();
    if (hash !== user.passwordHash) {
      throw new UnauthorizedException('Invalid email or password');
    }

    const accessToken = this.generateAccessToken({
      id: user.id,
      email: user.email,
      role: user.role,
      preferredLanguage: user.preferredLanguage,
    });
    const refreshToken = this.generateRefreshToken(user.id);

    // Store hashed refresh token in DB
    await this.storeRefreshToken(user.id, refreshToken);

    return {
      user: {
        id: user.id,
        email: user.email,
        name: user.name ?? 'User',
        role: user.role,
        preferredLanguage: user.preferredLanguage,
      },
      accessToken,
      refreshToken,
    };
  }

  /**
   * Refresh token — with DB-backed rotation
   * 1. Verify the JWT
   * 2. Check if the refresh token hash exists in DB for this user and is not expired
   * 3. If valid: generate new access + refresh tokens
   * 4. Store new refresh token in DB, invalidate old one
   * 5. If invalid: throw UnauthorizedException
   */
  async refresh(refreshToken: string) {
    try {
      // 1. Verify the JWT
      const payload = this.jwtService.verify(refreshToken, {
        secret: process.env.JWT_REFRESH_SECRET || 'kinrel-refresh-secret-change-in-production',
      });

      const userId = payload.sub;

      // 2. Check if the refresh token hash exists in DB and is not expired
      const tokenHash = this.hashToken(refreshToken);
      const user = await this.prisma.user.findUnique({
        where: { id: userId },
        select: {
          id: true,
          email: true,
          name: true,
          role: true,
          preferredLanguage: true,
          refreshToken: true,
          refreshTokenExp: true,
        },
      });

      if (!user) {
        throw new UnauthorizedException('Invalid refresh token');
      }

      // Verify the stored token matches the provided one
      if (user.refreshToken !== tokenHash) {
        // Token reuse detected — invalidate all refresh tokens for this user
        await this.prisma.user.update({
          where: { id: userId },
          data: { refreshToken: null, refreshTokenExp: null },
        });
        throw new UnauthorizedException('Invalid refresh token — possible token reuse detected');
      }

      // Verify token is not expired in DB
      if (user.refreshTokenExp && new Date() > user.refreshTokenExp) {
        await this.prisma.user.update({
          where: { id: userId },
          data: { refreshToken: null, refreshTokenExp: null },
        });
        throw new UnauthorizedException('Refresh token expired');
      }

      // 3. Generate new access + refresh tokens
      const accessToken = this.generateAccessToken({
        id: user.id,
        email: user.email,
        role: user.role,
        preferredLanguage: user.preferredLanguage,
      });
      const newRefreshToken = this.generateRefreshToken(user.id);

      // 4. Store new refresh token in DB, invalidate old one
      await this.storeRefreshToken(user.id, newRefreshToken);

      return {
        accessToken,
        refreshToken: newRefreshToken,
        user: {
          id: user.id,
          email: user.email,
          name: user.name ?? 'User',
          role: user.role,
          preferredLanguage: user.preferredLanguage,
        },
      };
    } catch (error) {
      if (error instanceof UnauthorizedException) {
        throw error;
      }
      throw new UnauthorizedException('Invalid or expired refresh token');
    }
  }

  /**
   * Google Sign-In (verify ID token from Flutter)
   */
  async googleLogin(idToken: string) {
    // For now, basic implementation
    // In production, verify the Google ID token using google-auth-library
    throw new BadRequestException('Google OAuth not yet configured. Please use email/password.');
  }

  /**
   * Logout — invalidate refresh token in DB
   */
  async logout(userId: string) {
    await this.prisma.user.update({
      where: { id: userId },
      data: { refreshToken: null, refreshTokenExp: null },
    });
    return { success: true, message: 'Logged out successfully' };
  }

  /**
   * Validate user by ID (used by JWT strategy)
   */
  async validateUser(userId: string) {
    return this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        preferredLanguage: true,
      },
    });
  }

  /**
   * Store hashed refresh token in DB with expiration
   */
  private async storeRefreshToken(userId: string, refreshToken: string) {
    const tokenHash = this.hashToken(refreshToken);
    // Refresh token expires in 7 days by default
    const expiresIn = process.env.JWT_REFRESH_EXPIRES_IN || '7d';
    const expiresMs = this.parseExpiry(expiresIn);
    const refreshTokenExp = new Date(Date.now() + expiresMs);

    await this.prisma.user.update({
      where: { id: userId },
      data: {
        refreshToken: tokenHash,
        refreshTokenExp,
      },
    });
  }

  /**
   * Hash a token using SHA-256
   */
  private hashToken(token: string): string {
    return CryptoJS.SHA256(token).toString();
  }

  /**
   * Parse JWT expiry string (e.g., '7d', '15m', '1h') to milliseconds
   */
  private parseExpiry(expiry: string): number {
    const match = expiry.match(/^(\d+)([smhd])$/);
    if (!match) return 7 * 24 * 60 * 60 * 1000; // default 7 days
    const value = parseInt(match[1], 10);
    const unit = match[2];
    switch (unit) {
      case 's': return value * 1000;
      case 'm': return value * 60 * 1000;
      case 'h': return value * 60 * 60 * 1000;
      case 'd': return value * 24 * 60 * 60 * 1000;
      default: return 7 * 24 * 60 * 60 * 1000;
    }
  }

  private generateAccessToken(user: { id: string; email: string; role: string; preferredLanguage: string }) {
    return this.jwtService.sign(
      {
        sub: user.id,
        email: user.email,
        role: user.role,
        preferredLanguage: user.preferredLanguage,
      },
      {
        secret: process.env.JWT_SECRET || 'kinrel-dev-secret-change-in-production',
        expiresIn: (process.env.JWT_EXPIRES_IN || '15m') as any,
      },
    );
  }

  private generateRefreshToken(userId: string) {
    return this.jwtService.sign(
      { sub: userId },
      {
        secret: process.env.JWT_REFRESH_SECRET || 'kinrel-refresh-secret-change-in-production',
        expiresIn: (process.env.JWT_REFRESH_EXPIRES_IN || '7d') as any,
      },
    );
  }
}
