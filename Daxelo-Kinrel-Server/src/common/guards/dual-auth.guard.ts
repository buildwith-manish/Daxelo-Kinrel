import {
  Injectable,
  CanActivate,
  ExecutionContext,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Reflector } from '@nestjs/core';
import { PrismaService } from '../prisma/prisma.service';
import { ApiKeyGuard } from './api-key.guard';
import { SCOPES_KEY } from '../decorators/scopes.decorator';
import { createHash } from 'crypto';

/**
 * DualAuthGuard — Accepts either JWT session auth OR API key auth.
 *
 * Strategy:
 * 1. If the Bearer token starts with `kin_`, try API key auth
 * 2. Otherwise, try JWT auth
 * 3. If the primary method fails, try the other method
 * 4. If both fail, deny the request
 *
 * Usage: @UseGuards(DualAuthGuard)
 */
@Injectable()
export class DualAuthGuard implements CanActivate {
  private readonly logger = new Logger(DualAuthGuard.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();

    // Check if Authorization header contains a Bearer token
    const authHeader = request.headers['authorization'];
    const token =
      authHeader?.startsWith('Bearer ') ? authHeader.substring(7) : null;

    // If it looks like an API key (starts with kin_), try API key auth first
    if (token && token.startsWith('kin_')) {
      try {
        return await this.tryApiKeyAuth(context, token);
      } catch {
        // API key auth failed, try JWT
        this.logger.debug('API key auth failed, trying JWT...');
      }
    }

    // Try JWT auth
    try {
      return await this.tryJwtAuth(context);
    } catch {
      // JWT auth failed
      this.logger.debug('JWT auth failed');
    }

    // If JWT failed and we haven't tried API key yet, try it now
    if (token && !token.startsWith('kin_')) {
      try {
        return await this.tryApiKeyAuth(context, token);
      } catch {
        // Both failed
      }
    }

    throw new UnauthorizedException(
      'Invalid or expired authentication token',
    );
  }

  /**
   * Try JWT authentication using Passport's jwt strategy
   */
  private async tryJwtAuth(
    context: ExecutionContext,
  ): Promise<boolean> {
    const jwtGuard = new (class extends AuthGuard('jwt') {
      handleRequest<TUser = any>(err: any, user: TUser): TUser {
        if (err || !user) {
          throw err || new UnauthorizedException('Invalid JWT token');
        }
        return user;
      }
    })();

    const result = await jwtGuard.canActivate(context);
    return result as boolean;
  }

  /**
   * Try API key authentication
   */
  private async tryApiKeyAuth(
    context: ExecutionContext,
    token: string,
  ): Promise<boolean> {
    const apiKeyGuard = new ApiKeyGuard(this.prisma, this.reflector);
    // Set the token on the request for ApiKeyGuard to process
    const request = context.switchToHttp().getRequest();
    if (!request.headers['authorization']?.startsWith('Bearer ')) {
      request.headers['authorization'] = `Bearer ${token}`;
    }
    return await apiKeyGuard.canActivate(context);
  }
}
