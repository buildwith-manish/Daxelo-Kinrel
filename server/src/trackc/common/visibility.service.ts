// =============================================================================
// Track C v2.0 — Common: Role & Age Visibility Helpers
// visibility.service.ts
// =============================================================================
// Pure helpers + an injectable service that implements the role- and age-based
// visibility matrix for the Kinrel Governance module.
//
// AGE RULE (fail-open, not fail-closed):
//   - `isMinorUser(dateOfBirth)` returns true ONLY when dateOfBirth is known
//     AND the computed age is < 18 years.
//   - null dateOfBirth → treated as ADULT (not minor). This is deliberate:
//     many existing families have incomplete profiles, and fail-closed would
//     lock those users out of governance actions. The matrix blocks minors
//     from edit/vote/create, so fail-open only relaxes the minor check —
//     the role check (viewer vs member) is still enforced.
//
// ROLE RULE:
//   - 'owner' | 'admin' | 'elder' | 'member' can act (edit/vote/create).
//   - 'viewer' is read-only for all 6 modules.
//   - These helpers do NOT change any role — they only CHECK.
// =============================================================================

import {
  Injectable,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import {
  FamilyMembershipService,
  FamilyRole,
} from './family-membership.service';

// ── Pure helpers (exported for unit testing) ─────────────────────────────

/**
 * The age threshold (in years) at which a user is no longer a minor.
 * 18 is the legal age of majority in India (where Kinrel is primarily used).
 */
export const MINOR_AGE_THRESHOLD = 18;

/**
 * Pure helper: returns true if the user is a minor (age < 18).
 *
 * @param dateOfBirth — the User.dateOfBirth value (nullable DateTime).
 *   - null → returns FALSE (fail-open: treated as adult). This avoids
 *     locking existing families with incomplete profiles out of
 *     governance actions.
 *   - Invalid date → returns FALSE (same fail-open rationale).
 *   - Valid date with age < 18 → returns TRUE.
 *   - Valid date with age >= 18 → returns FALSE.
 */
export function isMinorUser(dateOfBirth: Date | null | undefined): boolean {
  if (!dateOfBirth) return false;
  const dob = dateOfBirth instanceof Date ? dateOfBirth : new Date(dateOfBirth);
  if (isNaN(dob.getTime())) return false;

  const now = new Date();
  let age = now.getUTCFullYear() - dob.getUTCFullYear();
  const monthDiff = now.getUTCMonth() - dob.getUTCMonth();
  if (monthDiff < 0 || (monthDiff === 0 && now.getUTCDate() < dob.getUTCDate())) {
    age--;
  }
  return age < MINOR_AGE_THRESHOLD;
}

/**
 * The set of roles that can perform governance ACTIONS (edit, vote, create).
 * 'viewer' is excluded — they are read-only across all 6 modules.
 */
export const ACTION_ROLES: ReadonlySet<FamilyRole> = new Set<FamilyRole>([
  'owner',
  'admin',
  'elder',
  'member',
]);

/**
 * The set of roles that can access admin-level data (raw timeline log,
 * raw learning profile, per-member analytics).
 */
export const ADMIN_ROLES: ReadonlySet<FamilyRole> = new Set<FamilyRole>([
  'owner',
  'admin',
]);

/**
 * Convenience: is the role a "viewer" (read-only)?
 */
export function isViewerRole(role: string): boolean {
  return role?.toLowerCase() === 'viewer';
}

/**
 * Convenience: does this role permit governance actions (edit/vote/create)?
 */
export function canActByRole(role: string): boolean {
  return ACTION_ROLES.has(role as FamilyRole);
}

/**
 * Convenience: does this role permit admin-level data access?
 */
export function isAdminRole(role: string): boolean {
  return ADMIN_ROLES.has(role as FamilyRole);
}

// ── Injected service ─────────────────────────────────────────────────────

/**
 * Result of a membership + age lookup. Returned by requireMemberWithAge().
 */
export interface MembershipContext {
  /** The FamilyMember row id. */
  id: string;
  /** The family id. */
  familyId: string;
  /** The user id. */
  userId: string;
  /** The user's role in the family (owner|admin|elder|member|viewer). */
  role: FamilyRole;
  /** The user's dateOfBirth (null if unknown). */
  dateOfBirth: Date | null;
  /** Whether the user is a minor (age < 18, fail-open for null DOB). */
  isMinor: boolean;
  /** Whether the user can perform governance actions (non-viewer, non-minor). */
  canAct: boolean;
  /** Whether the user has admin-level data access (owner or admin). */
  isAdmin: boolean;
}

@Injectable()
export class VisibilityService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly membership: FamilyMembershipService,
  ) {}

  /**
   * Verify family membership AND fetch the user's dateOfBirth in a single
   * round-trip. Returns a MembershipContext with all pre-computed flags.
   *
   * This is the single entry point for all visibility checks — every
   * Track C service method that needs role/age gating should call this
   * first, then branch on the returned flags.
   */
  async requireMemberWithAge(userId: string, familyId: string): Promise<MembershipContext> {
    // 1. Verify membership (throws NotFoundException if not a member)
    const member = await this.membership.requireMember(userId, familyId);
    const role = member.role as FamilyRole;

    // 2. Fetch the user's dateOfBirth (single column query)
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { dateOfBirth: true },
    });
    const dateOfBirth = user?.dateOfBirth ?? null;
    const isMinor = isMinorUser(dateOfBirth);

    return {
      id: member.id,
      familyId,
      userId,
      role,
      dateOfBirth,
      isMinor,
      canAct: canActByRole(role) && !isMinor,
      isAdmin: isAdminRole(role),
    };
  }

  /**
   * Require that the user can perform governance ACTIONS (edit/vote/create).
   * Throws ForbiddenException if the user is a viewer OR a minor.
   *
   * Used by:
   *   - Constitution: saveDraft, publish, openAmendment (vote path goes
   *     through DecisionsService.vote which also calls this)
   *   - Decisions: create, vote, resolve, cancel
   *   - Secretary: create, editDraft
   */
  async requireCanAct(userId: string, familyId: string): Promise<MembershipContext> {
    const ctx = await this.requireMemberWithAge(userId, familyId);
    if (!ctx.canAct) {
      if (isViewerRole(ctx.role)) {
        throw new ForbiddenException(
          'Viewers cannot perform this action — ask a family admin to upgrade your role.',
        );
      }
      if (ctx.isMinor) {
        throw new ForbiddenException(
          'Family members under 18 cannot perform this governance action.',
        );
      }
      throw new ForbiddenException('You do not have permission to perform this action.');
    }
    return ctx;
  }

  /**
   * Require admin-level data access (owner or admin only).
   * Used by:
   *   - Timeline: ?raw=true (full unfiltered log)
   *   - Learning: getProfile (raw behavior profile)
   *   - Analytics: per-member breakdowns (future-proof guard)
   */
  async requireAdminDataAccess(userId: string, familyId: string): Promise<MembershipContext> {
    const ctx = await this.requireMemberWithAge(userId, familyId);
    if (!ctx.isAdmin) {
      throw new ForbiddenException(
        'This data is only available to family admins and owners.',
      );
    }
    return ctx;
  }
}
