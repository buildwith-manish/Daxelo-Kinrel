import { Injectable, CanActivate, ExecutionContext, UnauthorizedException, ForbiddenException, HttpException, HttpStatus } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { PrismaService } from '../../prisma/prisma.service';
import { API_SCOPE_KEY } from '../decorators/api-key-scope.decorator';
import { checkRateLimit } from '../../common/helpers/rate-limiter.helper';
import * as crypto from 'crypto';

@Injectable()
export class ApiKeyGuard implements CanActivate {
  constructor(
    private reflector: Reflector,
    private prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const authHeader = request.headers['authorization'] as string;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing or invalid Authorization header. Use: Bearer <api_key>');
    }

    const rawKey = authHeader.substring(7); // Remove 'Bearer '

    // Hash the provided key
    const keyHash = crypto.createHash('sha256').update(rawKey).digest('hex');

    // Look up the key by hash
    const apiKey = await this.prisma.apiKey.findFirst({
      where: { keyHash },
    });

    if (!apiKey) {
      throw new UnauthorizedException('Invalid API key');
    }

    // Check if revoked
    if (apiKey.revokedAt) {
      throw new UnauthorizedException('API key has been revoked');
    }

    // Check if expired
    if (apiKey.expiresAt && apiKey.expiresAt < new Date()) {
      throw new UnauthorizedException('API key has expired');
    }

    // Check required scope
    const requiredScope = this.reflector.getAllAndOverride<string>(API_SCOPE_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    if (requiredScope && requiredScope !== '*') {
      const scopes = JSON.parse(apiKey.scopes) as string[];
      if (!scopes.includes(requiredScope) && !scopes.includes('*')) {
        throw new ForbiddenException(`API key lacks required scope: ${requiredScope}`);
      }
    }

    // Rate limit
    const rateResult = checkRateLimit(apiKey.id, apiKey.tier, 'api');
    if (!rateResult.allowed) {
      throw new HttpException(
        {
          error: 'RATE_LIMITED',
          message: 'Rate limit exceeded',
          retryAfter: rateResult.retryAfter,
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
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
      scopes: JSON.parse(apiKey.scopes),
      tier: apiKey.tier,
      rateLimitPerMinute: apiKey.rateLimitPerMinute,
    };

    return true;
  }
}
