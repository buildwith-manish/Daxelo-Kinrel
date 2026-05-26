/**
 * KINREL — Kinship Validator Service
 *
 * Lightweight validation of relationship keys against the kinship module.
 * Used by API routes to validate user-submitted relationship types.
 */

import { Injectable } from '@nestjs/common';
import { KinshipService } from './kinship.service';

@Injectable()
export class KinshipValidatorService {
  private validKeys: Set<string>;

  constructor(private kinshipService: KinshipService) {
    // Build a Set for O(1) lookup at module load time
    this.validKeys = new Set(kinshipService.ALL_RELATIONSHIP_KEYS);
  }

  /**
   * Check if a relationship key is valid (after normalization).
   * Accepts both new format (fathers_elder_brother) and legacy (chacha).
   */
  isValidRelationshipKey(key: string): boolean {
    const normalized = this.kinshipService.normalizeRelationshipKey(key);
    return this.validKeys.has(normalized);
  }

  /**
   * Normalize and validate — returns the normalized key or null if invalid.
   */
  validateAndNormalizeKey(key: string): string | null {
    const normalized = this.kinshipService.normalizeRelationshipKey(key);
    return this.validKeys.has(normalized) ? normalized : null;
  }
}
