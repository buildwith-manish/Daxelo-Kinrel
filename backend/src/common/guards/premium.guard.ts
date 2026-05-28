import { Injectable, CanActivate, ExecutionContext, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class PremiumGuard implements CanActivate {
  constructor(private prisma: PrismaService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const user = request.user;

    if (!user) {
      throw new ForbiddenException('Premium subscription required');
    }

    // Check the DB for current premium status (not JWT, which could be stale)
    const dbUser = await this.prisma.user.findUnique({
      where: { id: user.id },
      select: { isPremium: true },
    });

    if (!dbUser || !dbUser.isPremium) {
      throw new ForbiddenException('Premium subscription required');
    }

    return true;
  }
}
