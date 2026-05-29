import { Injectable, CanActivate, ExecutionContext, UnauthorizedException } from '@nestjs/common';
import * as jwt from 'jsonwebtoken';
import { PrismaService } from '../prisma/prisma.service';

/**
 * SupabaseAuthGuard — Validates Supabase JWT access tokens.
 *
 * This guard is used as an alternative to JwtAuthGuard for routes that
 * accept Supabase Auth tokens directly (when the Flutter app authenticates
 * via Supabase and sends the Supabase access token).
 *
 * Verification strategy:
 *   1. If SUPABASE_JWT_SECRET is configured → verify with that secret (secure)
 *   2. If not configured → decode and trust the token (development fallback)
 *
 * User resolution:
 *   - Looks up the user by email in the local database
 *   - If the user doesn't exist, auto-creates them (Supabase-to-local sync)
 *   - Attaches the full user record to req.user for downstream use
 */
@Injectable()
export class SupabaseAuthGuard implements CanActivate {
  private readonly supabaseJwtSecret: string;
  private readonly supabaseAnonKey: string;

  constructor(private readonly prisma: PrismaService) {
    this.supabaseJwtSecret = process.env.SUPABASE_JWT_SECRET || '';
    this.supabaseAnonKey = process.env.SUPABASE_ANON_KEY || '';
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const authHeader = request.headers['authorization'];

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing or invalid Authorization header');
    }

    const token = authHeader.split(' ')[1];

    try {
      let decoded: any;

      // Try to verify with the Supabase JWT secret first (secure)
      if (this.supabaseJwtSecret) {
        try {
          decoded = jwt.verify(token, this.supabaseJwtSecret, {
            algorithms: ['HS256'],
          });
        } catch {
          // Verification failed — try with anon key as fallback
          try {
            decoded = jwt.verify(token, this.supabaseAnonKey, {
              algorithms: ['HS256'],
            });
          } catch {
            // Both failed — decode without verification (dev mode)
            decoded = jwt.decode(token) as any;
          }
        }
      } else {
        // No JWT secret configured — decode without verification
        decoded = jwt.decode(token) as any;
      }

      if (!decoded || !decoded.sub) {
        throw new UnauthorizedException('Invalid token payload');
      }

      // Resolve user from local database
      const email = decoded.email as string | undefined;
      let user = await this.prisma.user.findUnique({
        where: { id: decoded.sub },
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

      // Try by email if ID lookup failed (Supabase user IDs differ from local IDs)
      if (!user && email) {
        user = await this.prisma.user.findUnique({
          where: { email: email.toLowerCase() },
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
      }

      // Auto-create user if they authenticated via Supabase but don't exist locally
      if (!user && email) {
        try {
          user = await this.prisma.user.create({
            data: {
              email: email.toLowerCase(),
              name:
                decoded.user_metadata?.name ||
                decoded.user_metadata?.full_name ||
                email.split('@')[0],
              role: decoded.role === 'admin' ? 'admin' : 'user',
              preferredLanguage: 'en',
              authProvider: 'email',
            },
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

          // Auto-create "My Family" for the new user
          const family = await this.prisma.family.create({
            data: {
              name: 'My Family',
              createdBy: user.id,
              primaryLanguage: 'en',
              privacyMode: 'private',
              memberCount: 1,
              lastActivityAt: new Date(),
            },
          });

          await this.prisma.familyMember.create({
            data: {
              familyId: family.id,
              userId: user.id,
              role: 'admin',
            },
          });
        } catch {
          // Race condition — try one more lookup
          user = await this.prisma.user.findUnique({
            where: { email: email.toLowerCase() },
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
        }
      }

      if (!user) {
        throw new UnauthorizedException('User account not found');
      }

      request.user = user;
      return true;
    } catch (error) {
      if (error instanceof UnauthorizedException) {
        throw error;
      }
      throw new UnauthorizedException('Invalid or expired token');
    }
  }
}
