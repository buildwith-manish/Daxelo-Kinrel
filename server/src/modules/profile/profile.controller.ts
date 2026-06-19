import {
  Controller,
  Get,
  Patch,
  Param,
  Query,
  Body,
  UseGuards,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { ProfileService } from './profile.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { UpdatePrivacySettingsDto, KinshipGraphQueryDto } from './dto/update-privacy.dto';

@ApiTags('profile')
@Controller('profile')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class ProfileController {
  constructor(private readonly profileService: ProfileService) {}

  @Get(':familyId/:personId')
  @ApiOperation({
    summary: 'Get member profile with integrated kinship information',
    description: 'Returns a comprehensive member profile combining personal data, privacy settings, computed kinship relationships with multilingual translations, and kinship summary statistics. Privacy-filtered based on viewer role.',
  })
  @ApiResponse({ status: 200, description: 'Profile with kinship data' })
  @ApiResponse({ status: 403, description: 'Not authorized to view this profile' })
  @ApiResponse({ status: 404, description: 'Person not found' })
  @ApiQuery({ name: 'locale', required: false, description: 'Locale code for kinship terms (e.g., "hi", "mr", "ta")' })
  @ApiQuery({ name: 'includeTranslations', required: false, description: 'Include multilingual translations for all kinship terms' })
  async getProfileWithKinship(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
    @Query('locale') locale?: string,
    @Query('includeTranslations') includeTranslations?: string,
  ) {
    return this.profileService.getProfileWithKinship(userId, familyId, personId, {
      locale,
      includeTranslations: includeTranslations === 'true',
    });
  }

  @Get(':familyId/:personId/kinship')
  @ApiOperation({
    summary: 'Get kinship graph for a member',
    description: 'Returns all computed kinship relationships for a member with multilingual translations, kinship coefficients, and relationship classifications. Supports filtering by category, lineage, relation type, and coefficient threshold.',
  })
  @ApiResponse({ status: 200, description: 'Kinship graph data' })
  @ApiResponse({ status: 403, description: 'Not authorized' })
  @ApiResponse({ status: 404, description: 'Person not found' })
  async getKinshipGraph(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
    @Query() query: KinshipGraphQueryDto,
  ) {
    return this.profileService.getKinshipGraph(userId, familyId, personId, {
      category: query.category,
      lineage: query.lineage,
      relationType: query.relationType,
      minCoefficient: query.minCoefficient,
      maxDistance: query.maxDistance,
      includeTranslations: query.includeTranslations === 'true',
      locale: query.locale,
    });
  }

  @Get(':familyId/:personId/summary')
  @ApiOperation({
    summary: 'Get kinship summary statistics for a member',
    description: 'Returns summary statistics including total relationships, kinship coefficient distribution, closest relationship, and lineage breakdown. Useful for profile cards and dashboard widgets.',
  })
  @ApiResponse({ status: 200, description: 'Kinship summary statistics' })
  @ApiResponse({ status: 403, description: 'Not authorized' })
  @ApiResponse({ status: 404, description: 'Person not found' })
  async getKinshipSummary(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
  ) {
    return this.profileService.getKinshipSummary(userId, familyId, personId);
  }

  @Patch(':familyId/:personId/privacy')
  @ApiOperation({
    summary: 'Update privacy settings for a person',
    description: 'Update the privacy settings for a person. Only the person themselves or a family admin can update settings. All changes are logged for audit.',
  })
  @ApiResponse({ status: 200, description: 'Privacy settings updated' })
  @ApiResponse({ status: 403, description: 'Not authorized to update privacy settings' })
  @ApiResponse({ status: 404, description: 'Person not found' })
  async updatePrivacySettings(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
    @Body() dto: UpdatePrivacySettingsDto,
  ) {
    return this.profileService.updatePrivacySettings(userId, familyId, personId, dto);
  }
}
