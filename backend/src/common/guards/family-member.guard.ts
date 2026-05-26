import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Inject,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { PrismaService } from '../../prisma/prisma.service';

export const FAMILY_MEMBER_KEY = 'familyMember';
export const MIN_ROLE_KEY = 'minRole';

/**
 * Family role hierarchy: admin > editor > member > viewer
 */
const FAMILY_ROLE_HIERARCHY: Record<string, number> = {
  viewer: 1,
  member: 2,
  editor: 3,
  admin: 4,
};

@Injectable()
export class FamilyMemberGuard implements CanActivate {
  constructor(
    private reflector: Reflector,
    @Inject(PrismaService) private prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    // Check if guard is explicitly disabled
    const isFamilyMember = this.reflector.getAllAndOverride<boolean>(
      FAMILY_MEMBER_KEY,
      [context.getHandler(), context.getClass()],
    );

    if (isFamilyMember === false) {
      return true;
    }

    const request = context.switchToHttp().getRequest();
    const user = request.user;
    const familyId = request.params.familyId || request.body?.familyId;

    if (!user || !familyId) {
      throw new ForbiddenException('Access denied: missing user or family context');
    }

    const membership = await this.prisma.familyMember.findUnique({
      where: {
        familyId_userId: {
          familyId,
          userId: user.id,
        },
      },
    });

    if (!membership) {
      throw new ForbiddenException('You are not a member of this family');
    }

    // Check minimum role requirement
    const minRole = this.reflector.getAllAndOverride<string>(MIN_ROLE_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    if (minRole) {
      const userLevel = FAMILY_ROLE_HIERARCHY[membership.role] || 0;
      const requiredLevel = FAMILY_ROLE_HIERARCHY[minRole] || 0;

      if (userLevel < requiredLevel) {
        throw new ForbiddenException(
          `Insufficient permissions. Required: ${minRole}, current: ${membership.role}`,
        );
      }
    }

    // Attach membership to request for downstream use
    request.familyMembership = membership;
    return true;
  }
}
