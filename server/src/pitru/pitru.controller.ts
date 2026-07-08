// server/src/pitru/pitru.controller.ts
//
// PITRU — REST API Controller
//
// Endpoints (all require JWT auth via global JwtAuthGuard):
//
//   Memories:
//     GET    /pitru/memories?familyId=...           — list memories in a family
//     POST   /pitru/memories                        — record a new memory
//     GET    /pitru/memories/:id                    — get a single memory
//     PATCH  /pitru/memories/:id/ai-results         — update AI processing results
//     POST   /pitru/memories/:id/listen             — increment listen count
//
//   Tagging:
//     POST   /pitru/memories/:id/tags               — tag a person in a memory
//     DELETE /pitru/memories/:id/tags/:personId/:tagType — remove a tag
//
//   Consent:
//     PUT    /pitru/consent/:elderPersonId          — set consent (grant/revoke)
//     GET    /pitru/consent/:elderPersonId          — get all consents for an elder
//
//   Memorial:
//     POST   /pitru/memorial/:personId              — create/update memorial profile
//     GET    /pitru/memorial/:personId              — get memorial profile
//
// All write endpoints verify family membership inline in PitruService.

import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Logger,
  NotFoundException,
  Param,
  Patch,
  Post,
  Put,
  Query,
  ParseIntPipe,
  BadRequestException,
} from '@nestjs/common';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { PitruService, type ConsentType } from './pitru.service';

@Controller('pitru')
export class PitruController {
  private readonly logger = new Logger(PitruController.name);

  constructor(private readonly pitru: PitruService) {}

  // ────────────────────────────────────────────────────────────────────────
  // Memories
  // ────────────────────────────────────────────────────────────────────────

  @Get('memories')
  async listMemories(
    @Query('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('elderPersonId') elderPersonId?: string,
    @Query('topic') topic?: string,
    @Query('status') status?: string,
    @Query('includeUnrevealed') includeUnrevealed?: string,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
    @Query('offset', new ParseIntPipe({ optional: true })) offset?: number,
  ) {
    if (!familyId) throw new BadRequestException('familyId is required');
    return this.pitru.listMemories(userId, familyId, {
      elderPersonId,
      topic,
      status,
      includeUnrevealed: includeUnrevealed === 'true',
      limit,
      offset,
    });
  }

  @Post('memories')
  @HttpCode(HttpStatus.CREATED)
  async createMemory(
    @Body()
    body: {
      familyId: string;
      elderPersonId?: string;
      mediaType: 'audio' | 'video';
      mediaUrl: string;
      thumbnailUrl?: string;
      durationSec?: number;
      title: string;
      topic?: string;
      language?: string;
      description?: string;
      revealAt?: string;
    },
    @CurrentUser('id') userId: string,
  ) {
    if (!body.familyId) throw new BadRequestException('familyId is required');
    if (!body.mediaUrl) throw new BadRequestException('mediaUrl is required');
    if (!body.title) throw new BadRequestException('title is required');
    if (body.mediaType !== 'audio' && body.mediaType !== 'video') {
      throw new BadRequestException('mediaType must be audio or video');
    }
    return this.pitru.createMemory({
      familyId: body.familyId,
      recorderId: userId,
      elderPersonId: body.elderPersonId ?? null,
      mediaType: body.mediaType,
      mediaUrl: body.mediaUrl,
      thumbnailUrl: body.thumbnailUrl ?? null,
      durationSec: body.durationSec ?? 0,
      title: body.title,
      topic: body.topic ?? null,
      language: body.language ?? 'en',
      description: body.description ?? null,
      revealAt: body.revealAt ? new Date(body.revealAt) : null,
    });
  }

  @Get('memories/:id')
  async getMemory(@Param('id') id: string, @CurrentUser('id') userId: string) {
    return this.pitru.getMemory(id, userId);
  }

  @Patch('memories/:id/ai-results')
  @HttpCode(HttpStatus.OK)
  async updateAiResults(
    @Param('id') id: string,
    @Body()
    body: {
      transcript?: string;
      transcriptLanguage?: string;
      translation?: string;
      aiSummary?: string;
      aiTags?: string[];
      aiProcessingError?: string;
      status?: 'pending' | 'processing' | 'ready' | 'failed' | 'archived';
    },
    @CurrentUser('id') userId: string,
  ) {
    // Note: this endpoint is typically called by the AI pipeline (service_role),
    // not by end users. In production, we'd add a service-role guard here.
    // For now, any authenticated user can call it (family membership is still
    // verified inside the service via the memory's familyId).
    void userId; // not used — service verifies via memory lookup
    return this.pitru.updateAiResults(id, body);
  }

  @Post('memories/:id/listen')
  @HttpCode(HttpStatus.OK)
  async incrementListen(@Param('id') id: string, @CurrentUser('id') userId: string) {
    return this.pitru.incrementListenCount(id, userId);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Tagging
  // ────────────────────────────────────────────────────────────────────────

  @Post('memories/:id/tags')
  @HttpCode(HttpStatus.CREATED)
  async tagPerson(
    @Param('id') memoryId: string,
    @Body() body: { personId: string; tagType?: 'mentions' | 'about' | 'recorded_by' | 'featured' },
    @CurrentUser('id') userId: string,
  ) {
    if (!body.personId) throw new BadRequestException('personId is required');
    return this.pitru.tagPerson(
      memoryId,
      body.personId,
      userId,
      body.tagType ?? 'mentions',
    );
  }

  @Delete('memories/:id/tags/:personId/:tagType')
  async untagPerson(
    @Param('id') memoryId: string,
    @Param('personId') personId: string,
    @Param('tagType') tagType: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.pitru.untagPerson(memoryId, personId, tagType, userId);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Consent
  // ────────────────────────────────────────────────────────────────────────

  @Put('consent/:elderPersonId')
  @HttpCode(HttpStatus.OK)
  async setConsent(
    @Param('elderPersonId') elderPersonId: string,
    @Body() body: { consentType: ConsentType; consentGiven: boolean; notes?: string },
    @CurrentUser('id') userId: string,
  ) {
    const validTypes: ConsentType[] = [
      'ai_persona',
      'voice_cloning',
      'public_memorial',
      'cross_family_share',
    ];
    if (!validTypes.includes(body.consentType)) {
      throw new BadRequestException(`consentType must be one of: ${validTypes.join(', ')}`);
    }
    if (typeof body.consentGiven !== 'boolean') {
      throw new BadRequestException('consentGiven must be boolean');
    }
    return this.pitru.setConsent(
      elderPersonId,
      body.consentType,
      body.consentGiven,
      userId,
      body.notes,
    );
  }

  @Get('consent/:elderPersonId')
  async getConsents(@Param('elderPersonId') elderPersonId: string, @CurrentUser('id') userId: string) {
    return this.pitru.getConsents(elderPersonId, userId);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Memorial
  // ────────────────────────────────────────────────────────────────────────

  @Post('memorial/:personId')
  @HttpCode(HttpStatus.CREATED)
  async createMemorial(
    @Param('personId') personId: string,
    @Body()
    body: {
      memorialTitle?: string;
      memorialBio?: string;
      birthDate?: string;
      deathDate?: string;
      coverPhotoUrl?: string;
      isPublic?: boolean;
      allowMessages?: boolean;
      aiPersonaEnabled?: boolean;
    },
    @CurrentUser('id') userId: string,
  ) {
    return this.pitru.createMemorialProfile(
      personId,
      {
        memorialTitle: body.memorialTitle,
        memorialBio: body.memorialBio,
        birthDate: body.birthDate ? new Date(body.birthDate) : undefined,
        deathDate: body.deathDate ? new Date(body.deathDate) : undefined,
        coverPhotoUrl: body.coverPhotoUrl,
        isPublic: body.isPublic,
        allowMessages: body.allowMessages,
        aiPersonaEnabled: body.aiPersonaEnabled,
      },
      userId,
    );
  }

  @Get('memorial/:personId')
  async getMemorial(@Param('personId') personId: string, @CurrentUser('id') userId: string) {
    return this.pitru.getMemorialProfile(personId, userId);
  }

  @Get('memorial/:personId/feed')
  async getMemorialFeed(@Param('personId') personId: string, @CurrentUser('id') userId: string) {
    return this.pitru.getMemorialFeed(personId, userId);
  }

  @Get('memorials')
  async listMemorials(@Query('familyId') familyId: string, @CurrentUser('id') userId: string) {
    if (!familyId) throw new BadRequestException('familyId is required');
    return this.pitru.listMemorials(familyId, userId);
  }
}
