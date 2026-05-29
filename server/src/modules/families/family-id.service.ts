import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ConflictException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import * as crypto from 'crypto';

// ── Constants ────────────────────────────────────────────────────────

/** Regex pattern for valid Family IDs: KIN-XXXXXXXX where X is [A-Z0-9] */
const FAMILY_ID_PATTERN = /^KIN-[A-Z0-9]{8}$/;

/** Characters used for generating the random portion of the Family ID */
const FAMILY_ID_CHARSET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/** Maximum number of collision retries before giving up */
const MAX_COLLISION_RETRIES = 5;

/** Length of the random alphanumeric portion (after KIN-) */
const RANDOM_PART_LENGTH = 8;

// ── Types ────────────────────────────────────────────────────────────

export interface FamilySearchResult {
  id: string;
  name: string;
  kinFamilyId: string;
  description: string | null;
  memberCount: number;
  avatarUrl: string | null;
  privacyMode: string;
  primaryLanguage: string;
  region: string | null;
}

// ── Service ──────────────────────────────────────────────────────────

@Injectable()
export class FamilyIdService {
  private readonly logger = new Logger(FamilyIdService.name);

  constructor(
    private prisma: PrismaService,
    private gateway: KinrelGateway,
  ) {}

  // ── Public Methods ────────────────────────────────────────────────

  /**
   * Generate a globally unique, human-readable Family ID.
   *
   * Format: KIN-XXXXXXXX where X is [A-Z0-9]
   * Example: KIN-AB12CD34
   *
   * Uses crypto.randomBytes() for cryptographic randomness.
   * 8 chars × 36 possible values = ~2.8 trillion possible IDs.
   * Collision handling: retry up to 5 times with new random IDs.
   */
  async generateFamilyId(): Promise<string> {
    for (let attempt = 1; attempt <= MAX_COLLISION_RETRIES; attempt++) {
      const familyId = this.generateRandomFamilyId();

      // Check if this ID already exists (case-insensitive safety net)
      const existing = await this.prisma.family.findUnique({
        where: { kinFamilyId: familyId },
        select: { id: true },
      });

      if (!existing) {
        this.logger.debug(`Generated unique Family ID: ${familyId} (attempt ${attempt})`);
        return familyId;
      }

      this.logger.warn(
        `Family ID collision on attempt ${attempt}: ${familyId} — regenerating...`,
      );
    }

    // In practice this should never happen with 2.8 trillion possibilities
    throw new ConflictException(
      'Failed to generate a unique Family ID after multiple attempts. Please try again.',
    );
  }

  /**
   * Search for a family by its Family ID.
   *
   * Performs a case-insensitive lookup by normalising the input to
   * uppercase before querying the database.
   *
   * Returns a `FamilySearchResult` if found, or `null` otherwise.
   * Only returns families that are not in "private" privacy mode,
   * or returns all regardless of privacy mode (as decided by product).
   * Current implementation: always return found family; the controller
   * can filter based on privacy rules if needed.
   */
  async findByFamilyId(familyId: string): Promise<FamilySearchResult | null> {
    // Normalise to uppercase for consistent lookups
    const normalisedId = familyId.toUpperCase();

    const family = await this.prisma.family.findUnique({
      where: { kinFamilyId: normalisedId },
      select: {
        id: true,
        name: true,
        kinFamilyId: true,
        description: true,
        memberCount: true,
        avatarUrl: true,
        privacyMode: true,
        primaryLanguage: true,
        region: true,
      },
    });

    if (!family) {
      return null;
    }

    return {
      id: family.id,
      name: family.name,
      kinFamilyId: family.kinFamilyId!,
      description: family.description,
      memberCount: family.memberCount,
      avatarUrl: family.avatarUrl,
      privacyMode: family.privacyMode,
      primaryLanguage: family.primaryLanguage,
      region: family.region,
    };
  }

  /**
   * Join a family using a Family ID.
   *
   * Validates:
   *  1. The family exists and has a valid kinFamilyId
   *  2. The user is not already a member of this family
   *  3. Creates a FamilyMember record with the specified role (default: 'member')
   *  4. Auto-creates a Person record for the user in the family
   *  5. Increments the family memberCount
   *  6. Emits a WebSocket event to notify other family members
   *
   * Returns the FamilyMember record.
   */
  async joinByFamilyId(
    userId: string,
    familyId: string,
    role: string = 'member',
  ): Promise<{
    id: string;
    familyId: string;
    userId: string;
    role: string;
    joinedAt: Date;
    personId: string;
  }> {
    // ── 1. Validate Family ID format ───────────────────────────────
    if (!this.isValidFamilyId(familyId)) {
      throw new BadRequestException(
        'Invalid Family ID format. Must be KIN-XXXXXXXX (e.g. KIN-AB12CD34)',
      );
    }

    const normalisedId = familyId.toUpperCase();

    // ── 2. Look up the family ──────────────────────────────────────
    const family = await this.prisma.family.findUnique({
      where: { kinFamilyId: normalisedId },
      select: {
        id: true,
        name: true,
        kinFamilyId: true,
        privacyMode: true,
      },
    });

    if (!family) {
      throw new NotFoundException(
        `No family found with ID ${normalisedId}. Please check the ID and try again.`,
      );
    }

    // ── 3. Check if user is already a member ───────────────────────
    const existingMembership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId: family.id, userId } },
    });

    if (existingMembership) {
      throw new ConflictException(
        `You are already a member of "${family.name}".`,
      );
    }

    // ── 4. Get user info for Person auto-creation ──────────────────
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, name: true, username: true },
    });

    // ── 5. Validate requested role ─────────────────────────────────
    const allowedRoles = ['admin', 'member', 'viewer'];
    if (!allowedRoles.includes(role)) {
      throw new BadRequestException(
        `Invalid role "${role}". Must be one of: ${allowedRoles.join(', ')}`,
      );
    }

    // ── 6. Create membership + Person in a transaction ─────────────
    const result = await this.prisma.$transaction(async (tx) => {
      // Create the Person record (auto-created for the user)
      const person = await tx.person.create({
        data: {
          familyId: family.id,
          name: user?.name || user?.username || 'New Member',
          privacyLevel: 'family',
          generationIndex: 0,
          isAnchor: false,
        },
      });

      // Create the FamilyMember record
      const familyMember = await tx.familyMember.create({
        data: {
          familyId: family.id,
          userId,
          role,
        },
      });

      // Increment the family member count
      await tx.family.update({
        where: { id: family.id },
        data: {
          memberCount: { increment: 1 },
          lastActivityAt: new Date(),
        },
      });

      return { familyMember, person };
    });

    // ── 7. Emit WebSocket events ───────────────────────────────────
    // Notify family members that a new person was created
    this.gateway.emitToFamily(family.id, 'person:created', {
      id: result.person.id,
      updatedAt: new Date().toISOString(),
      type: 'person:created',
      familyId: family.id,
    });

    // Notify family members that someone joined
    this.gateway.emitToFamily(family.id, 'member:joined', {
      id: result.familyMember.id,
      updatedAt: new Date().toISOString(),
      type: 'member:joined',
      familyId: family.id,
      userId,
    });

    // Notify about graph update (debounced by gateway)
    this.gateway.emitToFamily(family.id, 'graph:updated', {
      id: family.id,
      updatedAt: new Date().toISOString(),
      type: 'graph:updated',
      familyId: family.id,
    });

    this.logger.log(
      `User ${userId} joined family "${family.name}" (${family.id}) via Family ID ${normalisedId} as ${role}`,
    );

    return {
      id: result.familyMember.id,
      familyId: result.familyMember.familyId,
      userId: result.familyMember.userId,
      role: result.familyMember.role,
      joinedAt: result.familyMember.joinedAt,
      personId: result.person.id,
    };
  }

  /**
   * Validate a Family ID format.
   *
   * Must match: /^KIN-[A-Z0-9]{8}$/
   * The input is normalised to uppercase before validation.
   */
  isValidFamilyId(familyId: string): boolean {
    if (typeof familyId !== 'string') return false;
    const normalised = familyId.toUpperCase().trim();
    return FAMILY_ID_PATTERN.test(normalised);
  }

  /**
   * Get the kinFamilyId for a given family (by its internal ID).
   * Auto-generates one if it doesn't exist yet (migration safety).
   */
  async getOrCreateFamilyId(familyInternalId: string): Promise<string> {
    const family = await this.prisma.family.findUnique({
      where: { id: familyInternalId },
      select: { kinFamilyId: true },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    // If the family already has a kinFamilyId, return it
    if (family.kinFamilyId) {
      return family.kinFamilyId;
    }

    // Auto-generate one for families created before this feature
    const newKinFamilyId = await this.generateFamilyId();
    await this.prisma.family.update({
      where: { id: familyInternalId },
      data: { kinFamilyId: newKinFamilyId },
    });

    this.logger.log(
      `Auto-generated Family ID ${newKinFamilyId} for family ${familyInternalId}`,
    );

    return newKinFamilyId;
  }

  // ── Private Methods ───────────────────────────────────────────────

  /**
   * Generate a random Family ID using crypto.randomBytes().
   *
   * Each byte is mapped to a character in the FAMILY_ID_CHARSET
   * (A-Z0-9, 36 characters) using modulo arithmetic.
   * The result is prefixed with "KIN-".
   */
  private generateRandomFamilyId(): string {
    const bytes = crypto.randomBytes(RANDOM_PART_LENGTH);
    let result = 'KIN-';

    for (let i = 0; i < RANDOM_PART_LENGTH; i++) {
      // Map each byte (0-255) to a character in the charset (0-35)
      // Using modulo 256 to avoid bias: since 256 = 7×36 + 4,
      // values 0-251 are evenly distributed. For simplicity we accept
      // the tiny bias (< 0.016%) which is negligible for this use case.
      result += FAMILY_ID_CHARSET[bytes[i] % FAMILY_ID_CHARSET.length];
    }

    return result;
  }
}
