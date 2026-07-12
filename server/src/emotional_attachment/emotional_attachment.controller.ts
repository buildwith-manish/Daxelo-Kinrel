// server/src/emotional_attachment/emotional attachment.controller.ts
//
// emotional attachment features — REST API Controller
//
// Combines endpoints for:
//   A-6 Festival Intelligence
//   A-1 Blessing Chain
//   A-2 Time Capsule
//
// All endpoints require JWT auth via global JwtAuthGuard.

import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Logger,
  Param,
  Post,
  Query,
  ParseIntPipe,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { PrismaService } from '../prisma/prisma.service';
import { FestivalService } from './festival.service';
import { BlessingChainService, type CreateBlessingInput } from './blessing-chain.service';
import { TimeCapsuleService, type CreateTimeCapsuleInput } from './time-capsule.service';
import { FamilyQuestService } from './family-quest.service';
import { SilentAlarmService } from './silent-alarm.service';
import { FamilyChronicleService } from './family-chronicle.service';

@Controller('pulse')
export class EmotionalAttachmentController {
  private readonly logger = new Logger(EmotionalAttachmentController.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly festivalService: FestivalService,
    private readonly blessingChainService: BlessingChainService,
    private readonly timeCapsuleService: TimeCapsuleService,
    private readonly familyQuestService: FamilyQuestService,
    private readonly silentAlarmService: SilentAlarmService,
    private readonly familyChronicleService: FamilyChronicleService,
  ) {}

  /** Verify the user is an admin/owner of the family. Throws ForbiddenException if not. */
  private async assertFamilyAdmin(userId: string, familyId: string): Promise<void> {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
      select: { role: true },
    });
    if (!membership) {
      throw new ForbiddenException('You are not a member of this family');
    }
    if (membership.role !== 'admin' && membership.role !== 'owner') {
      throw new ForbiddenException('Admin access required');
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // A-6 Festival Intelligence
  // ────────────────────────────────────────────────────────────────────────

  /** Get festivals happening in the next N days. */
  @Get('festivals/upcoming')
  async getUpcomingFestivals(
    @Query('days', new ParseIntPipe({ optional: true })) days?: number,
    @Query('region') region?: string,
  ) {
    return this.festivalService.getUpcomingFestivals(days ?? 30, region);
  }

  /** Get festivals happening today. */
  @Get('festivals/today')
  async getFestivalsToday() {
    return this.festivalService.getFestivalsToday();
  }

  /** Get a specific festival by key. */
  @Get('festivals/:key')
  async getFestivalByKey(@Param('key') key: string) {
    const festival = await this.festivalService.getFestivalByKey(key);
    if (!festival) {
      return { error: 'Festival not found', key };
    }
    return festival;
  }

  /** Manually trigger the festival seed (admin only — in production, add a role guard). */
  @Post('festivals/seed')
  @HttpCode(HttpStatus.OK)
  async seedFestivals() {
    return this.festivalService.seedFestivals();
  }

  // ────────────────────────────────────────────────────────────────────────
  // A-1 Blessing Chain
  // ────────────────────────────────────────────────────────────────────────

  @Post('blessings')
  @HttpCode(HttpStatus.CREATED)
  async createBlessing(
    @Body() body: {
      familyId: string;
      elderPersonId: string;
      elderUserId?: string;
      recipientPersonId?: string;
      recipientUserId?: string;
      mediaType: 'text' | 'audio';
      textContent?: string;
      mediaUrl?: string;
      durationSec?: number;
      triggerType: 'birthday' | 'festival' | 'anniversary' | 'custom';
      triggerDate: string; // YYYY-MM-DD
      festivalKey?: string;
      language?: string;
      isRecurring?: boolean;
    },
    @CurrentUser('id') userId: string,
  ) {
    if (!body.familyId || !body.elderPersonId) {
      throw new BadRequestException('familyId and elderPersonId are required');
    }
    if (!body.triggerDate) {
      throw new BadRequestException('triggerDate is required (YYYY-MM-DD)');
    }
    return this.blessingChainService.createBlessing(
      {
        familyId: body.familyId,
        elderPersonId: body.elderPersonId,
        elderUserId: body.elderUserId,
        recipientPersonId: body.recipientPersonId,
        recipientUserId: body.recipientUserId,
        mediaType: body.mediaType,
        textContent: body.textContent,
        mediaUrl: body.mediaUrl,
        durationSec: body.durationSec,
        triggerType: body.triggerType,
        triggerDate: new Date(body.triggerDate),
        festivalKey: body.festivalKey,
        language: body.language,
        isRecurring: body.isRecurring,
      },
      userId,
    );
  }

  @Get('blessings')
  async listBlessings(
    @Query('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('status') status?: string,
    @Query('elderPersonId') elderPersonId?: string,
    @Query('recipientUserId') recipientUserId?: string,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
  ) {
    if (!familyId) throw new BadRequestException('familyId is required');
    return this.blessingChainService.listBlessings(userId, familyId, {
      status,
      elderPersonId,
      recipientUserId,
      limit,
    });
  }

  @Get('blessings/for-me')
  async getBlessingsForMe(@CurrentUser('id') userId: string) {
    return this.blessingChainService.getBlessingsForUser(userId);
  }

  @Post('blessings/:id/view')
  @HttpCode(HttpStatus.OK)
  async markBlessingViewed(@Param('id') id: string, @CurrentUser('id') userId: string) {
    return this.blessingChainService.markViewed(id, userId);
  }

  @Post('blessings/:id/cancel')
  @HttpCode(HttpStatus.OK)
  async cancelBlessing(
    @Param('id') id: string,
    @Body() body: { reason?: string },
    @CurrentUser('id') userId: string,
  ) {
    return this.blessingChainService.cancelBlessing(id, userId, body.reason);
  }

  // ────────────────────────────────────────────────────────────────────────
  // A-2 Time Capsule
  // ────────────────────────────────────────────────────────────────────────

  @Post('time-capsules')
  @HttpCode(HttpStatus.CREATED)
  async createTimeCapsule(
    @Body() body: {
      familyId: string;
      recipientPersonId?: string;
      recipientUserId?: string;
      mediaType: 'text' | 'photo' | 'video';
      textContent?: string;
      mediaUrl?: string;
      thumbnailUrl?: string;
      title: string;
      revealAt: string; // ISO date
      revealReason?: string;
      notifyOnReveal?: boolean;
    },
    @CurrentUser('id') userId: string,
  ) {
    if (!body.familyId || !body.title || !body.revealAt) {
      throw new BadRequestException('familyId, title, and revealAt are required');
    }
    return this.timeCapsuleService.createCapsule(
      {
        familyId: body.familyId,
        recipientPersonId: body.recipientPersonId,
        recipientUserId: body.recipientUserId,
        mediaType: body.mediaType,
        textContent: body.textContent,
        mediaUrl: body.mediaUrl,
        thumbnailUrl: body.thumbnailUrl,
        title: body.title,
        revealAt: new Date(body.revealAt),
        revealReason: body.revealReason,
        notifyOnReveal: body.notifyOnReveal,
      },
      userId,
    );
  }

  @Get('time-capsules')
  async listTimeCapsules(
    @Query('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('status') status?: string,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
  ) {
    if (!familyId) throw new BadRequestException('familyId is required');
    return this.timeCapsuleService.listCapsules(userId, familyId, { status, limit });
  }

  @Get('time-capsules/for-me')
  async getTimeCapsulesForMe(@CurrentUser('id') userId: string) {
    return this.timeCapsuleService.getCapsulesForUser(userId);
  }

  @Post('time-capsules/:id/view')
  @HttpCode(HttpStatus.OK)
  async markCapsuleViewed(@Param('id') id: string, @CurrentUser('id') userId: string) {
    return this.timeCapsuleService.markViewed(id, userId);
  }

  @Post('time-capsules/:id/cancel')
  @HttpCode(HttpStatus.OK)
  async cancelCapsule(@Param('id') id: string, @CurrentUser('id') userId: string) {
    return this.timeCapsuleService.cancelCapsule(id, userId);
  }

  // ────────────────────────────────────────────────────────────────────────
  // A-3 Family Quests
  // ────────────────────────────────────────────────────────────────────────

  @Get('quests/active')
  async getActiveQuests(@CurrentUser('id') userId: string) {
    return this.familyQuestService.getActiveQuests(userId);
  }

  @Get('quests/history')
  async getQuestHistory(
    @CurrentUser('id') userId: string,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
  ) {
    return this.familyQuestService.getQuestHistory(userId, limit ?? 20);
  }

  @Post('quests/:id/complete')
  @HttpCode(HttpStatus.OK)
  async completeQuest(@Param('id') id: string, @CurrentUser('id') userId: string) {
    return this.familyQuestService.completeQuest(id, userId);
  }

  @Post('quests/:id/skip')
  @HttpCode(HttpStatus.OK)
  async skipQuest(@Param('id') id: string, @CurrentUser('id') userId: string) {
    return this.familyQuestService.skipQuest(id, userId);
  }

  @Post('quests/generate')
  @HttpCode(HttpStatus.OK)
  async generateQuests(
    @CurrentUser('id') userId: string,
    @Query('familyId') familyId: string,
  ) {
    if (!familyId) throw new BadRequestException('familyId is required');
    await this.assertFamilyAdmin(userId, familyId);
    return this.familyQuestService.generateQuestsForFamily(familyId);
  }

  // ────────────────────────────────────────────────────────────────────────
  // A-4 Silent Alarms
  // ────────────────────────────────────────────────────────────────────────

  @Get('alarms')
  async getAlarms(@CurrentUser('id') userId: string) {
    return this.silentAlarmService.getAlarmsForUser(userId);
  }

  @Post('alarms/:id/acknowledge')
  @HttpCode(HttpStatus.OK)
  async acknowledgeAlarm(@Param('id') id: string, @CurrentUser('id') userId: string) {
    return this.silentAlarmService.acknowledgeAlarm(id, userId);
  }

  // ────────────────────────────────────────────────────────────────────────
  // A-7 Family Chronicle
  // ────────────────────────────────────────────────────────────────────────

  @Get('chronicle')
  async getChronicle(@Query('familyId') familyId: string, @CurrentUser('id') userId: string) {
    if (!familyId) throw new BadRequestException('familyId is required');
    return this.familyChronicleService.getChronicle(familyId, userId);
  }

  @Post('chronicle/generate')
  @HttpCode(HttpStatus.OK)
  async generateChronicle(
    @CurrentUser('id') userId: string,
    @Query('familyId') familyId: string,
  ) {
    if (!familyId) throw new BadRequestException('familyId is required');
    await this.assertFamilyAdmin(userId, familyId);
    return this.familyChronicleService.generateChronicle(familyId);
  }
}
