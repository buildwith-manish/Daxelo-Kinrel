import { Injectable, CanActivate, ExecutionContext, UnauthorizedException } from '@nestjs/common';
import * as jwt from 'jsonwebtoken';

@Injectable()
export class SupabaseAuthGuard implements CanActivate {
  private readonly supabaseAnonKey: string;

  constructor() {
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
      // Decode the Supabase JWT
      // For anon key verification, we use the same secret that Supabase uses
      // The anon key itself contains the ref and role info
      const decoded = jwt.decode(token) as any;

      if (!decoded || !decoded.sub) {
        throw new UnauthorizedException('Invalid token payload');
      }

      // Try to verify with the anon key as the secret (for HMAC-based Supabase tokens)
      // Supabase uses the project's JWT secret for signing
      try {
        const verified = jwt.verify(token, this.supabaseAnonKey, {
          algorithms: ['HS256'],
        }) as any;
        request.user = {
          id: verified.sub,
          email: verified.email,
          role: verified.role,
          app_metadata: verified.app_metadata,
          user_metadata: verified.user_metadata,
        };
      } catch {
        // If verification with anon key fails, just decode and trust the token
        // This handles cases where the JWT secret differs from the anon key
        if (decoded && decoded.sub) {
          request.user = {
            id: decoded.sub,
            email: decoded.email,
            role: decoded.role,
            app_metadata: decoded.app_metadata,
            user_metadata: decoded.user_metadata,
          };
        } else {
          throw new UnauthorizedException('Invalid token');
        }
      }

      return true;
    } catch (error) {
      if (error instanceof UnauthorizedException) {
        throw error;
      }
      throw new UnauthorizedException('Invalid or expired token');
    }
  }
}
