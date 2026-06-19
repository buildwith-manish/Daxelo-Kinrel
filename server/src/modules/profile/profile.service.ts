/**
 * Profile Service — Kinship Graph + Member Profile Integration
 * ══════════════════════════════════════════════════════════════════════
 *
 * This service integrates three data sources to produce a comprehensive
 * member profile with kinship information:
 *
 *   1. Person model (Prisma) — core profile data
 *   2. GraphEngineService — computed relationship paths and kinship terms
 *   3. KinshipService — multilingual translations for kinship terms
 *   4. PersonPrivacySetting (Prisma) — privacy controls per field
 *   5. PhotoConsent (Prisma) — photo usage consent tracking
 *
 * Privacy Filtering:
 *   - Viewer role determines which fields are visible
 *   - DataAccessLog records all profile access for audit
 *   - Fails closed: on error, deny access
 */

import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { GraphEngineService, ComputedRelationship } from '../graph/graph-engine.service';
import { KinshipService, KinshipTerm } from '../kinship/kinship.service';
import {
  computeKinshipCoefficient,
  classifyRelationship,
  determineLineage,
} from './utils/kinship-coefficient';
import { UpdatePrivacySettingsDto } from './dto/update-privacy.dto';

// ── Types ────────────────────────────────────────────────────────────

interface PersonRecord {
  id: string;
  familyId: string;
  name: string;
  gender: string | null;
  dateOfBirth: Date | null;
  city: string | null;
  gotra: string | null;
  isDeceased: boolean;
  deletedAt: Date | null;
  birthYear: number | null;
  occupation: string | null;
  privacyLevel: string;
  notes: string | null;
  sideOfFamily: string | null;
  generationIndex: number;
  isAnchor: boolean;
  photoUrl: string | null;
  photoThumb: string | null;
  username: string | null;
  bloodGroup?: string | null;
  education?: string | null;
  biography?: string | null;
  email?: string | null;
  phone?: string | null;
  address?: string | null;
  anniversaryDate?: Date | null;
}

interface PrivacyRecord {
  id: string;
  personId: string;
  visibility: string;
  searchable: boolean;
  matrimonialEligible: boolean;
  communityFeatures: boolean;
  minorFlag: boolean;
  photoConsent: boolean;
  healthConsent: boolean;
  gotraVisibility: string;
  showPhone: boolean;
  showEmail: boolean;
  showAddress: boolean;
  showDob: boolean;
  showAge: boolean;
  showOccupation: boolean;
  showEducation: boolean;
  showBloodGroup: boolean;
  showAnniversary: boolean;
  profileVisibleTo: string;
}

type ViewerRole = 'self' | 'admin' | 'member' | 'extended' | 'public';

@Injectable()
export class ProfileService {
  private readonly logger = new Logger(ProfileService.name);

  constructor(
    private prisma: PrismaService,
    private graphEngine: GraphEngineService,
    private kinshipService: KinshipService,
  ) {}

  // ══════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ══════════════════════════════════════════════════════════════════

  /**
   * Get a member's full profile with integrated kinship information.
   * This is the primary integration endpoint that combines:
   * - Person profile data (privacy-filtered)
   * - Privacy settings
   * - Computed kinship relationships with multilingual translations
   * - Kinship summary statistics
   */
  async getProfileWithKinship(
    userId: string,
    familyId: string,
    personId: string,
    options: {
      locale?: string;
      includeTranslations?: boolean;
    } = {},
  ) {
    // 1. Auth check — verify user is a family member
    const viewerRole = await this.resolveViewerRole(userId, familyId, personId);

    // 2. Load person profile
    const person = await this.loadPerson(familyId, personId);
    if (!person) {
      throw new NotFoundException('Person not found');
    }

    // 3. Load privacy settings
    const privacy = await this.loadOrCreatePrivacySettings(personId);

    // 4. Check if viewer can see this profile
    if (!this.canViewProfile(person, privacy, viewerRole)) {
      throw new ForbiddenException('You do not have permission to view this profile');
    }

    // 5. Compute kinship relationships
    let computedRelationships: ComputedRelationship[] = [];
    try {
      computedRelationships = await this.graphEngine.getAllRelationships(
        familyId,
        personId,
        6, // maxDepth
      );
    } catch (error) {
      this.logger.warn(
        `Failed to compute kinship graph for person ${personId}: ${error.message}`,
      );
      // Continue with empty kinship — profile is still useful
    }

    // 6. Enrich with kinship translations and coefficients
    const kinshipGraph = this.enrichKinshipRelationships(
      computedRelationships,
      options.locale,
      options.includeTranslations ?? false,
    );

    // 7. Compute kinship summary
    const kinshipSummary = this.computeKinshipSummary(kinshipGraph);

    // 8. Apply privacy filtering to person profile
    const filteredPerson = this.applyPrivacyFilter(person, privacy, viewerRole);

    // 9. Log data access for audit
    await this.logDataAccess(personId, userId, viewerRole, 'profile_view');

    // 10. Build and return integrated response
    return {
      person: filteredPerson,
      privacy: viewerRole === 'self' || viewerRole === 'admin' ? this.formatPrivacy(privacy) : null,
      kinshipSummary,
      kinshipGraph,
      viewerRole,
      readOnly: viewerRole === 'extended' || viewerRole === 'public',
    };
  }

  /**
   * Get the kinship graph for a member — all computed relationships
   * with multilingual translations, coefficients, and classifications.
   * Supports filtering by category, lineage, relationType, and coefficient.
   */
  async getKinshipGraph(
    userId: string,
    familyId: string,
    personId: string,
    query: {
      category?: string;
      lineage?: string;
      relationType?: string;
      minCoefficient?: string;
      maxDistance?: string;
      includeTranslations?: boolean;
      locale?: string;
    } = {},
  ) {
    // 1. Auth check
    const viewerRole = await this.resolveViewerRole(userId, familyId, personId);

    // 2. Verify person exists
    const person = await this.loadPerson(familyId, personId);
    if (!person) {
      throw new NotFoundException('Person not found');
    }

    // 3. Compute kinship relationships
    const computedRelationships = await this.graphEngine.getAllRelationships(
      familyId,
      personId,
      6,
    );

    // 4. Enrich with translations and coefficients
    let kinshipGraph = this.enrichKinshipRelationships(
      computedRelationships,
      query.locale,
      query.includeTranslations ?? false,
    );

    // 5. Apply filters
    if (query.category) {
      kinshipGraph = kinshipGraph.filter(
        (r) => r.category === query.category,
      );
    }
    if (query.lineage) {
      kinshipGraph = kinshipGraph.filter(
        (r) => r.lineage === query.lineage,
      );
    }
    if (query.relationType) {
      kinshipGraph = kinshipGraph.filter(
        (r) => r.relationType === query.relationType,
      );
    }
    if (query.minCoefficient) {
      const minCoeff = parseFloat(query.minCoefficient);
      if (!isNaN(minCoeff) && minCoeff >= 0 && minCoeff <= 1) {
        kinshipGraph = kinshipGraph.filter(
          (r) => r.kinshipCoefficient >= minCoeff,
        );
      }
    }
    if (query.maxDistance) {
      const maxDist = parseInt(query.maxDistance, 10);
      if (!isNaN(maxDist) && maxDist > 0) {
        kinshipGraph = kinshipGraph.filter(
          (r) => r.distance <= maxDist,
        );
      }
    }

    // 6. Compute summary
    const summary = this.computeKinshipSummary(kinshipGraph);

    // 7. Log access
    await this.logDataAccess(personId, userId, viewerRole, 'kinship_graph_view');

    return {
      items: kinshipGraph,
      total: kinshipGraph.length,
      summary,
    };
  }

  /**
   * Get kinship summary statistics for a member without the full graph.
   * Useful for quick profile cards and dashboard widgets.
   */
  async getKinshipSummary(userId: string, familyId: string, personId: string) {
    const viewerRole = await this.resolveViewerRole(userId, familyId, personId);

    const person = await this.loadPerson(familyId, personId);
    if (!person) {
      throw new NotFoundException('Person not found');
    }

    const computedRelationships = await this.graphEngine.getAllRelationships(
      familyId,
      personId,
      6,
    );

    const kinshipGraph = this.enrichKinshipRelationships(
      computedRelationships,
      undefined,
      false,
    );

    await this.logDataAccess(personId, userId, viewerRole, 'kinship_summary_view');

    return this.computeKinshipSummary(kinshipGraph);
  }

  /**
   * Update privacy settings for a person.
   * Only the person themselves or a family admin can update settings.
   */
  async updatePrivacySettings(
    userId: string,
    familyId: string,
    personId: string,
    dto: UpdatePrivacySettingsDto,
  ) {
    // Must be self or admin
    const viewerRole = await this.resolveViewerRole(userId, familyId, personId);
    if (viewerRole !== 'self' && viewerRole !== 'admin') {
      throw new ForbiddenException('Only the person themselves or a family admin can update privacy settings');
    }

    // Verify person exists
    const person = await this.loadPerson(familyId, personId);
    if (!person) {
      throw new NotFoundException('Person not found');
    }

    // Load or create privacy settings
    const existing = await this.loadOrCreatePrivacySettings(personId);

    // Build update data from DTO
    const updateData: Record<string, unknown> = {};
    if (dto.visibility !== undefined) updateData.visibility = dto.visibility;
    if (dto.searchable !== undefined) updateData.searchable = dto.searchable;
    if (dto.matrimonialEligible !== undefined) updateData.matrimonialEligible = dto.matrimonialEligible;
    if (dto.communityFeatures !== undefined) updateData.communityFeatures = dto.communityFeatures;
    if (dto.minorFlag !== undefined) updateData.minorFlag = dto.minorFlag;
    if (dto.photoConsent !== undefined) updateData.photoConsent = dto.photoConsent;
    if (dto.healthConsent !== undefined) updateData.healthConsent = dto.healthConsent;
    if (dto.gotraVisibility !== undefined) updateData.gotraVisibility = dto.gotraVisibility;
    if (dto.showPhone !== undefined) updateData.showPhone = dto.showPhone;
    if (dto.showEmail !== undefined) updateData.showEmail = dto.showEmail;
    if (dto.showAddress !== undefined) updateData.showAddress = dto.showAddress;
    if (dto.showDob !== undefined) updateData.showDob = dto.showDob;
    if (dto.showAge !== undefined) updateData.showAge = dto.showAge;
    if (dto.showOccupation !== undefined) updateData.showOccupation = dto.showOccupation;
    if (dto.showEducation !== undefined) updateData.showEducation = dto.showEducation;
    if (dto.showBloodGroup !== undefined) updateData.showBloodGroup = dto.showBloodGroup;
    if (dto.showAnniversary !== undefined) updateData.showAnniversary = dto.showAnniversary;
    if (dto.profileVisibleTo !== undefined) updateData.profileVisibleTo = dto.profileVisibleTo;

    // Update the record
    const updated = await this.prisma.personPrivacySetting.update({
      where: { personId },
      data: updateData,
    });

    // Log the privacy update
    await this.logDataAccess(personId, userId, viewerRole, 'privacy_update');

    this.logger.log(
      `Privacy settings updated for person ${personId} by user ${userId} (role: ${viewerRole})`,
    );

    return this.formatPrivacy(updated);
  }

  // ══════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ══════════════════════════════════════════════════════════════════

  /**
   * Resolve the viewer's role relative to the target person.
   * This determines what data they can see.
   */
  private async resolveViewerRole(
    userId: string,
    familyId: string,
    targetPersonId: string,
  ): Promise<ViewerRole> {
    // Check if user is a family member
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (!membership) {
      // Check if family is public
      const family = await this.prisma.family.findUnique({
        where: { id: familyId },
        select: { isPublic: true },
      });

      if (family?.isPublic) {
        return 'public';
      }

      throw new ForbiddenException('You are not a member of this family');
    }

    // Check if the target person belongs to the user
    // (a user can have multiple person records across families)
    const userPerson = await this.prisma.person.findFirst({
      where: { familyId, id: targetPersonId },
      select: { id: true },
    });

    // Check if this person is linked to the user via FamilyMember → Person
    // The user's own person in this family can be found via the username or other means
    // For now, check if user has a person record with their username
    const userRecord = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { username: true },
    });

    const ownPerson = await this.prisma.person.findFirst({
      where: {
        familyId,
        username: userRecord?.username ?? null,
        deletedAt: null,
      },
      select: { id: true },
    });

    if (ownPerson && ownPerson.id === targetPersonId) {
      return 'self';
    }

    if (membership.role === 'admin') {
      return 'admin';
    }

    return 'member';
  }

  /**
   * Load a person record from the database.
   */
  private async loadPerson(familyId: string, personId: string): Promise<PersonRecord | null> {
    return this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
      select: {
        id: true,
        familyId: true,
        name: true,
        gender: true,
        dateOfBirth: true,
        city: true,
        gotra: true,
        isDeceased: true,
        deletedAt: true,
        birthYear: true,
        occupation: true,
        privacyLevel: true,
        notes: true,
        sideOfFamily: true,
        generationIndex: true,
        isAnchor: true,
        photoUrl: true,
        photoThumb: true,
        username: true,
        bloodGroup: true,
        education: true,
        biography: true,
        email: true,
        phone: true,
        address: true,
        anniversaryDate: true,
      },
    }) as Promise<PersonRecord | null>;
  }

  /**
   * Load privacy settings for a person, creating defaults if none exist.
   */
  private async loadOrCreatePrivacySettings(personId: string): Promise<PrivacyRecord> {
    const existing = await this.prisma.personPrivacySetting.findUnique({
      where: { personId },
    });

    if (existing) {
      return existing as unknown as PrivacyRecord;
    }

    // Create default privacy settings
    const created = await this.prisma.personPrivacySetting.create({
      data: {
        personId,
        visibility: 'family',
        searchable: true,
        matrimonialEligible: true,
        communityFeatures: true,
        minorFlag: false,
        photoConsent: true,
        healthConsent: false,
        gotraVisibility: 'family',
        showPhone: false,
        showEmail: false,
        showAddress: false,
        showDob: true,
        showAge: true,
        showOccupation: true,
        showEducation: true,
        showBloodGroup: false,
        showAnniversary: false,
        profileVisibleTo: 'family',
      },
    });

    this.logger.debug(`Created default privacy settings for person ${personId}`);

    return created as unknown as PrivacyRecord;
  }

  /**
   * Check if a viewer can see a person's profile based on privacy settings.
   */
  private canViewProfile(
    person: PersonRecord,
    privacy: PrivacyRecord,
    viewerRole: ViewerRole,
  ): boolean {
    // Self and admin always have access
    if (viewerRole === 'self' || viewerRole === 'admin') return true;

    // Check profile visibility setting
    const visibleTo = privacy.profileVisibleTo;
    if (visibleTo === 'family' && (viewerRole === 'member')) return true;
    if (visibleTo === 'extended' && (viewerRole === 'member' || viewerRole === 'extended')) return true;
    if (visibleTo === 'public') return true;

    // Check person's own privacy level
    if (person.privacyLevel === 'public') return true;
    if (person.privacyLevel === 'extended' && viewerRole !== 'public') return true;
    if (person.privacyLevel === 'family' && viewerRole === 'member') return true;

    // Fail closed
    return viewerRole === 'member'; // Members can see other members by default
  }

  /**
   * Apply privacy filtering to person profile based on viewer role.
   * Removes or nullifies fields the viewer doesn't have permission to see.
   */
  private applyPrivacyFilter(
    person: PersonRecord,
    privacy: PrivacyRecord,
    viewerRole: ViewerRole,
  ): Record<string, unknown> {
    const result: Record<string, unknown> = {
      id: person.id,
      familyId: person.familyId,
      name: person.name,
      gender: person.gender ?? null,
      isDeceased: person.isDeceased,
      isAnchor: person.isAnchor,
      generationIndex: person.generationIndex,
      sideOfFamily: person.sideOfFamily ?? null,
      privacyLevel: person.privacyLevel,
      photoUrl: person.photoThumb ?? person.photoUrl ?? null,
      photoThumb: person.photoThumb ?? null,
      username: person.username ?? null,
    };

    // Self and admin see everything
    if (viewerRole === 'self' || viewerRole === 'admin') {
      result.dateOfBirth = person.dateOfBirth ?? null;
      result.city = person.city ?? null;
      result.gotra = person.gotra ?? null;
      result.birthYear = person.birthYear ?? null;
      result.occupation = person.occupation ?? null;
      result.email = person.email ?? null;
      result.phone = person.phone ?? null;
      result.address = person.address ?? null;
      result.bloodGroup = person.bloodGroup ?? null;
      result.anniversaryDate = person.anniversaryDate ?? null;
      result.education = person.education ?? null;
      result.biography = person.biography ?? null;
      result.notes = person.notes ?? null;
      return result;
    }

    // For member/extended/public, apply per-field privacy controls
    result.dateOfBirth = privacy.showDob ? (person.dateOfBirth ?? null) : null;
    result.birthYear = privacy.showAge ? (person.birthYear ?? null) : null;
    result.city = person.city ?? null;
    result.gotra = this.canShowGotra(privacy.gotraVisibility, viewerRole) ? (person.gotra ?? null) : null;
    result.occupation = privacy.showOccupation ? (person.occupation ?? null) : null;
    result.email = privacy.showEmail ? (person.email ?? null) : null;
    result.phone = privacy.showPhone ? (person.phone ?? null) : null;
    result.address = privacy.showAddress ? (person.address ?? null) : null;
    result.bloodGroup = privacy.showBloodGroup ? (person.bloodGroup ?? null) : null;
    result.anniversaryDate = privacy.showAnniversary ? (person.anniversaryDate ?? null) : null;
    result.education = privacy.showEducation ? (person.education ?? null) : null;
    // Biography and notes are always private unless viewer is self/admin
    result.biography = null;
    result.notes = null;

    return result;
  }

  /**
   * Check if gotra can be shown based on visibility setting and viewer role.
   */
  private canShowGotra(gotraVisibility: string, viewerRole: ViewerRole): boolean {
    if (gotraVisibility === 'hidden') return false;
    if (gotraVisibility === 'self') return viewerRole === 'self';
    if (gotraVisibility === 'admin') return viewerRole === 'self' || viewerRole === 'admin';
    if (gotraVisibility === 'family') return viewerRole !== 'public';
    return true;
  }

  /**
   * Enrich computed relationships with kinship translations and coefficients.
   * This is the core integration between GraphEngine and KinshipService.
   */
  private enrichKinshipRelationships(
    computedRelationships: ComputedRelationship[],
    locale?: string,
    includeTranslations: boolean = false,
  ): Array<{
    personId: string;
    personName: string;
    gender: string | null;
    relationshipKey: string;
    computedTerm: string;
    computedTermHindi: string;
    translations?: Record<string, { native: string; latin: string }>;
    kinshipCoefficient: number;
    distance: number;
    lineage: 'paternal' | 'maternal' | 'neutral';
    relationType: 'blood' | 'marital' | 'affinal';
    category?: string;
    isDeceased: boolean;
    photoThumb?: string | null;
    generationIndex?: number;
  }> {
    return computedRelationships.map((rel) => {
      // Compute kinship coefficient
      const kinshipCoefficient = computeKinshipCoefficient(
        rel.computedTerm,
        rel.path,
      );

      // Classify relationship
      const relationType = classifyRelationship(rel.computedTerm, rel.path);

      // Determine lineage
      const lineage = determineLineage(rel.path);

      // Try to find kinship translations from KinshipService
      let translations: Record<string, { native: string; latin: string }> | undefined;
      let category: string | undefined;

      // Try multiple key strategies to find the term in the kinship database
      const kinshipTerm = this.findKinshipTerm(rel.computedTerm, rel.relationshipKey);

      if (kinshipTerm) {
        category = kinshipTerm.relationshipCategory;

        if (includeTranslations || locale) {
          translations = {};
          for (const [langCode, translation] of Object.entries(kinshipTerm.translations)) {
            translations[langCode] = {
              native: translation.native,
              latin: translation.latin,
            };
          }
        }

        // If locale is specified, use the locale-specific term
        if (locale && kinshipTerm.translations[locale]) {
          // Already have computedTerm from graph engine; the locale translation
          // is available in the translations map for the consumer to use
        }
      }

      return {
        personId: rel.personId,
        personName: rel.personName,
        gender: null, // Will be populated if we load person data
        relationshipKey: rel.relationshipKey,
        computedTerm: rel.computedTerm,
        computedTermHindi: rel.computedTermHindi,
        ...(includeTranslations || locale ? { translations } : {}),
        kinshipCoefficient,
        distance: rel.distance,
        lineage,
        relationType,
        category,
        isDeceased: false, // Not available in ComputedRelationship
      };
    });
  }

  /**
   * Find a kinship term in the KinshipService by trying multiple key strategies.
   *
   * Strategy 1: Try the computed term directly (e.g., "cousin")
   * Strategy 2: Convert path key to possessive form (e.g., "father→brother→son" → "fathers_brothers_son")
   * Strategy 3: Try individual path components as keys
   */
  private findKinshipTerm(
    computedTerm: string,
    pathKey: string,
  ): KinshipTerm | null {
    try {
      // Strategy 1: Direct computed term lookup
      const directLookup = this.kinshipService.getByKey(computedTerm);
      if (directLookup) return directLookup;

      // Strategy 2: Convert path key to possessive form
      const possessiveKey = this.pathKeyToPossessiveKey(pathKey);
      if (possessiveKey) {
        const possessiveLookup = this.kinshipService.getByKey(possessiveKey);
        if (possessiveLookup) return possessiveLookup;
      }

      // Strategy 3: Try category-based composite keys
      const compositeKey = this.buildCompositeKey(computedTerm, pathKey);
      if (compositeKey && compositeKey !== computedTerm) {
        const compositeLookup = this.kinshipService.getByKey(compositeKey);
        if (compositeLookup) return compositeLookup;
      }

      return null;
    } catch {
      return null;
    }
  }

  /**
   * Convert a path key (e.g., "father→brother→son") to possessive form
   * (e.g., "fathers_brothers_son") for KinshipService lookup.
   */
  private pathKeyToPossessiveKey(pathKey: string): string | null {
    if (!pathKey || !pathKey.includes('→')) return null;

    const parts = pathKey.split('→');
    const possessiveParts: string[] = [];

    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      // All parts except the last get possessive form (add 's')
      if (i < parts.length - 1) {
        // Handle special cases
        if (part === 'wife') {
          possessiveParts.push('wives');
        } else if (part === 'brother' || part === 'father' || part === 'sister' || part === 'mother') {
          possessiveParts.push(part + 's'); // brothers, fathers, sisters, mothers
        } else {
          possessiveParts.push(part + 's');
        }
      } else {
        // Last part stays as-is
        possessiveParts.push(part);
      }
    }

    return possessiveParts.join('_');
  }

  /**
   * Build a composite key for category-based kinship lookup.
   * E.g., computedTerm="cousin", pathKey="father→brother→son" → "cousin_paternal_male"
   */
  private buildCompositeKey(computedTerm: string, pathKey: string): string | null {
    if (!pathKey || !pathKey.includes('→')) return null;

    const lineage = this.determineLineageFromKey(pathKey);
    const genderHint = this.inferGenderFromKey(pathKey);

    // Try lineage + gender composite
    if (lineage !== 'neutral' && genderHint) {
      return `${computedTerm}_${lineage}_${genderHint}`;
    }
    if (lineage !== 'neutral') {
      return `${computedTerm}_${lineage}`;
    }

    return null;
  }

  private determineLineageFromKey(pathKey: string): 'paternal' | 'maternal' | 'neutral' {
    const parts = pathKey.split('→');
    for (const part of parts) {
      if (part === 'father') return 'paternal';
      if (part === 'mother') return 'maternal';
      if (part === 'husband' || part === 'wife') continue;
      break;
    }
    return 'neutral';
  }

  private inferGenderFromKey(pathKey: string): 'male' | 'female' | null {
    const parts = pathKey.split('→');
    const lastPart = parts[parts.length - 1];
    const maleTerms = new Set(['son', 'brother', 'husband', 'father', 'nephew', 'grandson']);
    const femaleTerms = new Set(['daughter', 'sister', 'wife', 'mother', 'niece', 'granddaughter']);
    if (maleTerms.has(lastPart)) return 'male';
    if (femaleTerms.has(lastPart)) return 'female';
    return null;
  }

  /**
   * Compute kinship summary statistics from the enriched graph.
   */
  private computeKinshipSummary(kinshipGraph: Array<{ kinshipCoefficient: number; relationType: string; distance: number; computedTerm: string; computedTermHindi: string; personName: string }>) {
    const totalRelationships = kinshipGraph.length;
    let immediateFamily = 0;
    let extendedFamily = 0;
    let inLaws = 0;
    let byMarriage = 0;
    let bloodRelations = 0;
    let maritalRelations = 0;
    let affinalRelations = 0;
    let totalCoefficient = 0;
    let maxCoefficient = 0;
    let closestRelationship: { term: string; termHindi: string; coefficient: number; personName: string } | null = null;
    let maxDistance = 0;

    for (const rel of kinshipGraph) {
      // Count by relation type
      if (rel.relationType === 'blood') bloodRelations++;
      else if (rel.relationType === 'marital') maritalRelations++;
      else affinalRelations++;

      // Count by category
      if (rel.kinshipCoefficient >= 0.5) immediateFamily++;
      else if (rel.kinshipCoefficient > 0) extendedFamily++;
      else if (rel.relationType === 'affinal') inLaws++;
      else byMarriage++;

      // Coefficient statistics
      totalCoefficient += rel.kinshipCoefficient;
      if (rel.kinshipCoefficient > maxCoefficient) {
        maxCoefficient = rel.kinshipCoefficient;
        closestRelationship = {
          term: rel.computedTerm,
          termHindi: rel.computedTermHindi,
          coefficient: rel.kinshipCoefficient,
          personName: rel.personName,
        };
      }

      // Distance tracking
      if (rel.distance > maxDistance) {
        maxDistance = rel.distance;
      }
    }

    return {
      totalRelationships,
      immediateFamily,
      extendedFamily,
      inLaws,
      byMarriage,
      averageKinshipCoefficient: totalRelationships > 0
        ? Math.round((totalCoefficient / totalRelationships) * 10000) / 10000
        : 0,
      maxKinshipCoefficient: maxCoefficient,
      closestRelationship,
      kinshipDepth: maxDistance,
      bloodRelations,
      maritalRelations,
      affinalRelations,
    };
  }

  /**
   * Log data access for audit trail.
   */
  private async logDataAccess(
    personId: string,
    viewerId: string,
    viewerRole: ViewerRole,
    fieldAccessed: string,
  ): Promise<void> {
    try {
      await this.prisma.dataAccessLog.create({
        data: {
          personId,
          viewerId,
          viewerRole,
          fieldAccessed,
          granted: true,
        },
      });
    } catch (error) {
      // Don't fail the request if audit logging fails
      this.logger.warn(`Failed to log data access: ${error.message}`);
    }
  }

  /**
   * Format privacy settings for API response.
   */
  private formatPrivacy(privacy: PrivacyRecord): Record<string, unknown> {
    return {
      visibility: privacy.visibility,
      searchable: privacy.searchable,
      matrimonialEligible: privacy.matrimonialEligible,
      communityFeatures: privacy.communityFeatures,
      minorFlag: privacy.minorFlag,
      photoConsent: privacy.photoConsent,
      healthConsent: privacy.healthConsent,
      gotraVisibility: privacy.gotraVisibility,
      showPhone: privacy.showPhone,
      showEmail: privacy.showEmail,
      showAddress: privacy.showAddress,
      showDob: privacy.showDob,
      showAge: privacy.showAge,
      showOccupation: privacy.showOccupation,
      showEducation: privacy.showEducation,
      showBloodGroup: privacy.showBloodGroup,
      showAnniversary: privacy.showAnniversary,
      profileVisibleTo: privacy.profileVisibleTo,
    };
  }
}
