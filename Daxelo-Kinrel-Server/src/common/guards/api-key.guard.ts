import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
  Logger,
} from '@nestjs/common';
import type { Request } from 'express';
import { createHash } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { Reflector } from '@nestjs/core';
import { SCOPES_KEY } from '../decorators/scopes.decorator';

interface AuthenticatedRequest extends Request {
  user?: {
    id: string;
    email: string;
    role: string;
  };
  apiKey?: {
    id: string;
    userId: string;
    scopes: string[];
    tier: string;
  };
}

@Injectable()
export class ApiKeyGuard implements CanActivate {
  private readonly logger = new Logger(ApiKeyGuard.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();

    const authHeader = request.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing or invalid Authorization header');
    }

    const token = authHeader.substring(7); // Remove "Bearer " prefix

    // Validate token format: kin_live_XXXX...
    if (!token.startsWith('kin_')) {
      throw new UnauthorizedException('Invalid API key format');
    }

    const keyPrefix = token.substring(0, 12);
    const keyHash = createHash('sha256').update(token).digest('hex');

    // Look up the API key
    const apiKey = await this.prisma.apiKey.findUnique({
      where: { keyPrefix_keyHash: { keyPrefix, keyHash } },
    });

    if (!apiKey) {
      throw new UnauthorizedException('Invalid API key');
    }

    // Check if key is revoked
    if (apiKey.revokedAt) {
      throw new UnauthorizedException('API key has been revoked');
    }

    // Check if key is expired
    if (apiKey.expiresAt && new Date() > apiKey.expiresAt) {
      throw new UnauthorizedException('API key has expired');
    }

    // Check required scopes
    const requiredScopes = this.reflector.getAllAndOverride<string[]>(SCOPES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    if (requiredScopes && requiredScopes.length > 0) {
      const keyScopes = JSON.parse(apiKey.scopes) as string[];
      const hasScope = requiredScopes.every((scope) =>
        keyScopes.includes(scope),
      );
      if (!hasScope) {
        throw new UnauthorizedException('Insufficient API key scopes');
      }
    }

    // Update lastUsedAt
    await this.prisma.apiKey.update({
      where: { id: apiKey.id },
      data: { lastUsedAt: new Date() },
    });

    // Attach API key info to request
    request.apiKey = {
      id: apiKey.id,
      userId: apiKey.userId,
      scopes: JSON.parse(apiKey.scopes) as string[],
      tier: apiKey.tier,
    };

    // Also set user info from the API key owner
    const user = await this.prisma.user.findUnique({
      where: { id: apiKey.userId },
    });

    if (user) {
      request.user = {
        id: user.id,
        email: user.email,
        role: user.role,
      };
    }

    return true;
  }
}
