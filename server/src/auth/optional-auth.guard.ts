import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';
import * as jwt from 'jsonwebtoken';

@Injectable()
export class OptionalAuthGuard implements CanActivate {
  private readonly supabaseAnonKey: string;

  constructor() {
    this.supabaseAnonKey = process.env.SUPABASE_ANON_KEY || '';
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const authHeader = request.headers['authorization'];

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return true; // Allow unauthenticated access
    }

    const token = authHeader.split(' ')[1];

    try {
      let decoded: any;
      try {
        decoded = jwt.verify(token, this.supabaseAnonKey, {
          algorithms: ['HS256'],
        }) as any;
      } catch {
        decoded = jwt.decode(token) as any;
      }

      if (decoded && decoded.sub) {
        request.user = {
          id: decoded.sub,
          email: decoded.email,
          role: decoded.role,
          app_metadata: decoded.app_metadata,
          user_metadata: decoded.user_metadata,
        };
      }
    } catch {
      // Ignore errors for optional auth
    }

    return true;
  }
}
