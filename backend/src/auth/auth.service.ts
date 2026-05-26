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
    const { name, email, password } = dto;

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

    // Generate tokens
    const accessToken = this.generateAccessToken({
      id: user.id,
      email: user.email,
      role: 'user',
      preferredLanguage: 'en',
    });
    const refreshToken = this.generateRefreshToken(user.id);

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
   * Refresh token
   */
  async refresh(refreshToken: string) {
    try {
      const payload = this.jwtService.verify(refreshToken, {
        secret: process.env.JWT_REFRESH_SECRET || 'kinrel-refresh-secret-change-in-production',
      });

      const user = await this.prisma.user.findUnique({
        where: { id: payload.sub },
        select: { id: true, email: true, name: true, role: true, preferredLanguage: true },
      });

      if (!user) {
        throw new UnauthorizedException('Invalid refresh token');
      }

      const accessToken = this.generateAccessToken({
        id: user.id,
        email: user.email,
        role: user.role,
        preferredLanguage: user.preferredLanguage,
      });
      const newRefreshToken = this.generateRefreshToken(user.id);

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
    } catch {
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
   * Logout — client-side token invalidation
   */
  async logout() {
    // JWT is stateless; logout is handled client-side
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
