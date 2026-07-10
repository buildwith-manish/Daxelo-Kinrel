// =============================================================================
// Track C v2.0 — Kinrel Governance: Constitution
// constitution.controller.ts
// =============================================================================

import {
  Controller,
  Get,
  Post,
  Param,
  Body,
  UseGuards,
  BadRequestException,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { ConstitutionService, DraftConstitutionInput } from './constitution.service';

@Controller('v1/families/:familyId/constitution')
@UseGuards(JwtAuthGuard)
export class ConstitutionController {
  constructor(private readonly service: ConstitutionService) {}

  @Get()
  get(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.service.getConstitution(familyId, userId);
  }

  @Post('draft')
  saveDraft(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: DraftConstitutionInput,
  ) {
    if (!body?.title) throw new BadRequestException('title is required');
    if (!body?.articles?.length) throw new BadRequestException('articles must be non-empty');
    return this.service.saveDraft(familyId, userId, body);
  }

  @Post('publish')
  publish(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { changeSummary?: string },
  ) {
    return this.service.publish(familyId, userId, body?.changeSummary);
  }

  @Get('versions')
  versions(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.service.listVersions(familyId, userId);
  }

  @Get('versions/:versionId')
  version(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Param('versionId') versionId: string,
  ) {
    return this.service.getVersion(familyId, versionId, userId);
  }

  @Post('amend')
  amend(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { title: string; description: string; changeSummary: string; deadlineAt: string; quorumPct?: number },
  ) {
    if (!body?.title || !body?.description || !body?.deadlineAt) {
      throw new BadRequestException('title, description, and deadlineAt are required');
    }
    return this.service.openAmendment(familyId, userId, body);
  }
}
