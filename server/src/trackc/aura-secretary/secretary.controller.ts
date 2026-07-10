// =============================================================================
// Track C v2.0 — AURA Secretary
// secretary.controller.ts
// =============================================================================

import {
  Controller,
  Get,
  Post,
  Patch,
  Param,
  Body,
  Query,
  UseGuards,
  BadRequestException,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { SecretaryService, CreateArtifactInput } from './secretary.service';

@Controller('v1/families/:familyId/secretary/artifacts')
@UseGuards(JwtAuthGuard)
export class SecretaryController {
  constructor(private readonly service: SecretaryService) {}

  @Post()
  create(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: CreateArtifactInput,
  ) {
    if (!body?.title) throw new BadRequestException('title is required');
    return this.service.create(familyId, userId, body);
  }

  @Get()
  list(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('status') status?: string,
    @Query('limit') limit?: string,
  ) {
    return this.service.list(familyId, userId, {
      status,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  @Get(':artifactId')
  getOne(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Param('artifactId') artifactId: string,
  ) {
    return this.service.getOne(familyId, artifactId, userId);
  }

  @Patch(':artifactId/draft')
  editDraft(
    @Param('familyId') familyId: string,
    @Param('artifactId') artifactId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { draftMinutesMd: string },
  ) {
    if (body?.draftMinutesMd === undefined) throw new BadRequestException('draftMinutesMd is required');
    return this.service.editDraft(familyId, artifactId, userId, body.draftMinutesMd);
  }

  @Post(':artifactId/publish')
  publish(
    @Param('familyId') familyId: string,
    @Param('artifactId') artifactId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { finalMinutesMd?: string },
  ) {
    return this.service.publish(familyId, artifactId, userId, body?.finalMinutesMd);
  }
}
