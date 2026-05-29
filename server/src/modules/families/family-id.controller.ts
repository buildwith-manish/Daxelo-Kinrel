import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  UseGuards,
  HttpCode,
  HttpStatus,
  NotFoundException,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { FamilyIdService } from './family-id.service';
import { FamiliesService } from './families.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JoinFamilyDto, SearchFamilyDto } from './dto/join-family.dto';

/**
 * FamilyIdController — REST API for the Family ID System (Feature 1).
 *
 * Endpoints:
 *   POST /families/family-id/search   — Search family by Family ID (20 req/min)
 *   POST /families/family-id/join     — Join family by Family ID (5 req/min)
 *   GET  /families/:familyId/family-id — Get the Family ID for a family
 *
 * All endpoints require JWT authentication.
 */
@Controller('families')
@UseGuards(JwtAuthGuard)
export class FamilyIdController {
  constructor(
    private familyIdService: FamilyIdService,
    private familiesService: FamiliesService,
  ) {}

  /**
   * Search for a family by its Family ID.
   *
   * Rate limited to 20 requests per minute to prevent enumeration attacks.
   * Returns basic family info (name, member count, avatar) without
   * exposing sensitive data.
   *
   * POST /families/family-id/search
   */
  @Post('family-id/search')
  @HttpCode(HttpStatus.OK)
  @Throttle({ short: { limit: 20, ttl: 60000 }, long: { limit: 20, ttl: 60000 } })
  async searchByFamilyId(
    @CurrentUser('id') userId: string,
    @Body() dto: SearchFamilyDto,
  ) {
    // Normalise to uppercase for case-insensitive search
    const normalisedFamilyId = dto.familyId.toUpperCase();

    const result = await this.familyIdService.findByFamilyId(normalisedFamilyId);

    if (!result) {
      return {
        found: false,
        message: `No family found with ID ${normalisedFamilyId}`,
      };
    }

    return {
      found: true,
      family: {
        id: result.id,
        name: result.name,
        kinFamilyId: result.kinFamilyId,
        description: result.description,
        memberCount: result.memberCount,
        avatarUrl: result.avatarUrl,
        privacyMode: result.privacyMode,
        primaryLanguage: result.primaryLanguage,
        region: result.region,
      },
    };
  }

  /**
   * Join a family using a Family ID.
   *
   * Rate limited to 5 requests per minute to prevent spam joining.
   * Validates the family exists, the user is not already a member,
   * and creates a FamilyMember + Person record.
   *
   * POST /families/family-id/join
   */
  @Post('family-id/join')
  @HttpCode(HttpStatus.OK)
  @Throttle({ short: { limit: 5, ttl: 60000 }, long: { limit: 5, ttl: 60000 } })
  async joinByFamilyId(
    @CurrentUser('id') userId: string,
    @Body() dto: JoinFamilyDto,
  ) {
    const result = await this.familyIdService.joinByFamilyId(
      userId,
      dto.familyId,
      dto.role,
    );

    return {
      success: true,
      message: 'Successfully joined the family',
      membership: {
        id: result.id,
        familyId: result.familyId,
        role: result.role,
        joinedAt: result.joinedAt,
        personId: result.personId,
      },
    };
  }

  /**
   * Get the Family ID (KIN-XXXXXXXX) for a specific family.
   *
   * The user must be a member of the family to view its Family ID.
   * Auto-generates a Family ID if one doesn't exist yet (for families
   * created before this feature was introduced).
   *
   * GET /families/:familyId/family-id
   */
  @Get(':familyId/family-id')
  async getFamilyId(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    // Verify the user is a member of this family
    await this.familiesService.requireFamilyMember(userId, familyId);

    // Get or auto-generate the Family ID
    const kinFamilyId = await this.familyIdService.getOrCreateFamilyId(familyId);

    return {
      familyId,
      kinFamilyId,
    };
  }
}
