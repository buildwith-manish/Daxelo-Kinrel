/**
 * DAXELO KINREL — Dual Auth Guard
 *
 * Tries JWT authentication first, then falls back to Bearer API key.
 * Used by the Graph module which supports both session-based and API key auth.
 */

import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma/prisma.service';
import * as CryptoJS from 'crypto-js';

@Injectable()
export class DualAuthGuard implements CanActivate {
  constructor(
    private jwtService: JwtService,
    private prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const authHeader = request.headers['authorization'] as string | undefined;

    if (!authHeader) {
      throw new UnauthorizedException('Authorization header is required');
    }

    const parts = authHeader.split(' ');
    if (parts.length !== 2 || parts[0] !== 'Bearer') {
      throw new UnauthorizedException('Invalid authorization format. Use: Bearer <token>');
    }

    const token = parts[1];

    // Strategy 1: Try JWT first
    try {
      const payload = await this.jwtService.verifyAsync(token, {
        secret: process.env.JWT_SECRET || 'kinrel-dev-secret-change-in-production',
      });

      // Validate user still exists
      const user = await this.prisma.user.findUnique({
        where: { id: payload.sub },
        select: { id: true, email: true, name: true, role: true, preferredLanguage: true },
      });

      if (user) {
        request.user = user;
        return true;
      }
    } catch {
      // JWT failed, try API key
    }

    // Strategy 2: Fall back to API key
    const keyHash = CryptoJS.SHA256(token).toString();
    const keyPrefix = token.substring(0, 12);

    const apiKey = await this.prisma.apiKey.findFirst({
      where: {
        keyPrefix,
        keyHash,
        revokedAt: null,
        OR: [
          { expiresAt: null },
          { expiresAt: { gt: new Date() } },
        ],
      },
      include: {
        user: {
          select: { id: true, email: true, name: true, role: true, preferredLanguage: true },
        },
      },
    });

    if (!apiKey) {
      throw new UnauthorizedException('Invalid or expired token/API key');
    }

    // Update lastUsedAt
    await this.prisma.apiKey.update({
      where: { id: apiKey.id },
      data: { lastUsedAt: new Date() },
    });

    // Attach user to request
    request.user = apiKey.user;
    request.apiKey = apiKey;

    return true;
  }
}
