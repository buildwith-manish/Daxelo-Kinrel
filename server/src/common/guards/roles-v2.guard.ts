import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { PrismaService } from '../../prisma/prisma.service';

// ────────────────────────────────────────────────────────────────
// Family Role Type
// ────────────────────────────────────────────────────────────────

/**
 * FamilyRole — Roles within a family context.
 *
 * Hierarchy (highest to lowest privilege):
 *   owner  → can do everything: delete family, transfer ownership, manage billing
 *   admin  → can manage members, relationships, settings, invite people
 *   member → can add/edit persons, view everything
 *   viewer → can only view data
 */
export type FamilyRole = 'owner' | 'admin' | 'member' | 'viewer';

/**
 * Role weight mapping for hierarchical comparison.
 * Higher weight = more privileges.
 */
const ROLE_WEIGHT: Record<FamilyRole, number> = {
  owner: 4,
  admin: 3,
  member: 2,
  viewer: 1,
};

/**
 * Get the weight of a family role. Returns 0 for unknown roles.
 */
export function getRoleWeight(role: string): number {
  return ROLE_WEIGHT[role as FamilyRole] ?? 0;
}

/**
 * Check if `userRole` meets or exceeds the `requiredRole` privilege level.
 */
export function hasMinimumRole(
  userRole: string,
  requiredRole: FamilyRole,
): boolean {
  return getRoleWeight(userRole) >= ROLE_WEIGHT[requiredRole];
}

// ────────────────────────────────────────────────────────────────
// Metadata Key & Decorator
// ────────────────────────────────────────────────────────────────

export const FAMILY_ROLES_KEY = 'familyRoles';

/**
 * FamilyRoles — Decorator that sets required family roles for a route.
 *
 * Used together with RolesV2Guard to enforce family-scoped role-based
 * access control. Multiple roles are treated as "any of these roles"
 * (OR logic), BUT since roles are hierarchical, specifying multiple
 * roles means "the minimum of these roles is required."
 *
 * In practice, you should specify only the MINIMUM required role,
 * and the guard will automatically allow higher-privileged roles.
 *
 * @example
 *   @FamilyRoles('owner', 'admin')  // owner or admin required
 *   @FamilyRoles('admin')           // admin or above required
 *   @FamilyRoles('member')          // member or above required (viewers blocked)
 *   @FamilyRoles('viewer')          // any family member (all roles ≥ viewer)
 */
export const FamilyRoles = (...roles: FamilyRole[]) =>
  SetMetadata(FAMILY_ROLES_KEY, roles);

// ────────────────────────────────────────────────────────────────
// Authenticated Request Interface
// ────────────────────────────────────────────────────────────────

interface AuthenticatedRequest extends Request {
  user?: {
    id: string;
    email: string;
    role: string;
    [key: string]: any;
  };
  params?: Record<string, string>;
  query?: Record<string, string>;
  body?: Record<string, any>;
}

// ────────────────────────────────────────────────────────────────
// RolesV2Guard
// ────────────────────────────────────────────────────────────────

/**
 * RolesV2Guard — Enhanced family-scoped role-based access guard.
 *
 * This guard checks that the authenticated user has a sufficient role
 * within a specific family context. It differs from the original
 * RolesGuard in that:
 *
 * 1. It is family-scoped — it looks up the user's role in the
 *    FamilyMember table for the requested familyId.
 * 2. It supports hierarchical roles — specifying 'admin' will also
 *    allow 'owner' access (since owner ≥ admin).
 * 3. It extracts familyId from route params, query params, or body.
 *
 * Prerequisites:
 *   - JwtAuthGuard (or equivalent) must run BEFORE this guard to
 *     attach `req.user`.
 *   - The route must include a familyId in params, query, or body.
 *
 * Usage:
 *   @FamilyRoles('owner', 'admin')
 *   @UseGuards(JwtAuthGuard, RolesV2Guard)
 *   async createRelationship() { ... }
 *
 *   @FamilyRoles('member')
 *   @UseGuards(JwtAuthGuard, RolesV2Guard)
 *   async addPerson() { ... }
 */
@Injectable()
export class RolesV2Guard implements CanActivate {
  private readonly logger = new Logger(RolesV2Guard.name);

  constructor(
    private readonly reflector: Reflector,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    // ── 1. Get required roles from decorator ──────────────────────
    const requiredRoles = this.reflector.getAllAndOverride<FamilyRole[]>(
      FAMILY_ROLES_KEY,
      [context.getHandler(), context.getClass()],
    );

    // No @FamilyRoles() decorator → allow access (guard passes)
    if (!requiredRoles || requiredRoles.length === 0) {
      return true;
    }

    // ── 2. Get user from JWT (attached by JwtAuthGuard) ───────────
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const user = request.user;

    if (!user?.id) {
      throw new ForbiddenException('Authentication required');
    }

    // ── 3. Get familyId from params, query, or body ──────────────
    const familyId = this.extractFamilyId(request);

    if (!familyId) {
      this.logger.warn(
        `RolesV2Guard: No familyId found in request for user ${user.id}. ` +
          `Ensure familyId is in params, query, or body.`,
      );
      throw new ForbiddenException(
        'Family ID is required for role-based access control',
      );
    }

    // ── 4. Look up user's role in the family ─────────────────────
    const familyMember = await this.prisma.familyMember.findUnique({
      where: {
        familyId_userId: {
          familyId,
          userId: user.id,
        },
      },
      select: {
        role: true,
        familyId: true,
      },
    });

    if (!familyMember) {
      this.logger.warn(
        `RolesV2Guard: User ${user.id} is not a member of family ${familyId}`,
      );
      throw new ForbiddenException(
        'You are not a member of this family',
      );
    }

    const userRole = familyMember.role as FamilyRole;

    // ── 5. Check role hierarchy ──────────────────────────────────
    // The minimum required role is the LOWEST in the specified list.
    // Since roles are hierarchical, we check if the user's role
    // weight is >= the minimum required weight.
    const minimumRequiredWeight = Math.min(
      ...requiredRoles.map((r) => ROLE_WEIGHT[r]),
    );

    const userWeight = ROLE_WEIGHT[userRole] ?? 0;

    if (userWeight < minimumRequiredWeight) {
      this.logger.warn(
        `RolesV2Guard: User ${user.id} has role '${userRole}' ` +
          `(weight: ${userWeight}) in family ${familyId}, ` +
          `but requires minimum weight ${minimumRequiredWeight} ` +
          `(roles: ${requiredRoles.join(', ')})`,
      );
      throw new ForbiddenException(
        `Insufficient permissions. Your role: ${userRole}. ` +
          `Required: ${requiredRoles.join(' or ')} (or higher).`,
      );
    }

    // ── 6. Attach family role info to request for downstream use ──
    (request as any).familyRole = userRole;
    (request as any).familyId = familyId;

    return true;
  }

  /**
   * Extract familyId from the request.
   * Checks in order: params → query → body
   */
  private extractFamilyId(request: AuthenticatedRequest): string | null {
    // Check route params first (e.g., /families/:familyId/...)
    const params = (request as any).params;
    if (params?.familyId) {
      return params.familyId;
    }

    // Check query params (e.g., ?familyId=xxx)
    const query = (request as any).query;
    if (query?.familyId) {
      return query.familyId;
    }

    // Check request body (e.g., { familyId: "xxx", ... })
    const body = (request as any).body;
    if (body?.familyId) {
      return body.familyId;
    }

    return null;
  }
}
