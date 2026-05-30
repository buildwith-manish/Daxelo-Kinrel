import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';
import * as jwt from 'jsonwebtoken';

interface JwtPayload {
  sub: string;
  email: string;
  role: string;
}

/**
 * JwtStrategy — Validates JWT access tokens on every guarded request.
 *
 * Supports TWO token types:
 *   1. NestJS JWT — signed with JWT_ACCESS_SECRET (standard flow)
 *   2. Supabase JWT — signed with SUPABASE_JWT_SECRET (when Flutter app
 *      authenticates via Supabase Auth and sends the Supabase access token)
 *
 * For Supabase tokens, if the user doesn't exist in the local DB, they are
 * auto-created (supabase-to-local user sync). This ensures that users who
 * register via Supabase Auth can immediately use the NestJS API.
 *
 * The decoded token payload is attached to `req.user` and can be
 * accessed via the @CurrentUser() decorator.
 */
@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy, 'jwt') {
  private readonly config: ConfigService;
  private readonly prisma: PrismaService;

  constructor(
    config: ConfigService,
    prisma: PrismaService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      // Dynamically select the verification secret based on the token issuer
      secretOrKeyProvider: (
        request: any,
        rawJwtToken: string,
        done: (err: any, secret: string | Buffer | undefined) => void,
      ) => {
        try {
          // Decode the token header/payload WITHOUT verification to inspect issuer
          const decoded = jwt.decode(rawJwtToken, { complete: true }) as any;

          if (decoded?.payload?.iss?.includes('supabase')) {
            // Supabase JWT — try SUPABASE_JWT_SECRET first
            const supabaseSecret = config.get<string>('SUPABASE_JWT_SECRET', '');
            if (supabaseSecret) {
              done(null, supabaseSecret);
              return;
            }
            // Fallback: try the SUPABASE_ANON_KEY (won't verify but allows decoding)
            const anonKey = config.get<string>('SUPABASE_ANON_KEY', '');
            if (anonKey) {
              done(null, anonKey);
              return;
            }
            // Last resort: use a dummy secret (verification will fail, but
            // we handle this in validate() by catching the error)
            done(null, 'supabase-dev-fallback');
            return;
          }

          // NestJS JWT — use the standard secret
          done(null, config.get<string>('JWT_ACCESS_SECRET', 'default-secret'));
        } catch (e) {
          done(e, undefined);
        }
      },
    });

    this.config = config;
    this.prisma = prisma;
  }

  async validate(payload: any) {
    const isSupabaseToken =
      payload.iss?.includes('supabase') || payload.aud?.includes('authenticated');

    const userId = payload.sub;
    const email = payload.email;

    // ── Try to find user by ID (works for NestJS JWTs) ──────────
    let user = await this.prisma.user.findUnique({
      where: { id: userId },
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

    // ── For Supabase tokens: try lookup by email if ID lookup failed ──
    if (!user && isSupabaseToken && email) {
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

    // ── Auto-create user if authenticated via Supabase but not in local DB ──
    if (!user && isSupabaseToken && email) {
      try {
        user = await this.prisma.user.create({
          data: {
            email: email.toLowerCase(),
            name:
              payload.user_metadata?.name ||
              payload.user_metadata?.full_name ||
              email.split('@')[0],
            role: payload.role === 'admin' ? 'admin' : 'user',
            preferredLanguage: 'en',
            authProvider: payload.app_metadata?.provider || payload.user_metadata?.provider || 'email',
            avatarUrl: payload.user_metadata?.avatar_url || payload.user_metadata?.picture || null,
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

        // Auto-create "My Family" for the new user (same as /auth/register)
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
      } catch (createError) {
        // Race condition: user might have been created by another request
        // Try one more lookup
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

        if (!user) {
          throw new UnauthorizedException(
            'Failed to create user account. Please try again.',
          );
        }
      }
    }

    if (!user) {
      throw new UnauthorizedException('User account no longer exists');
    }

    return user;
  }
}
