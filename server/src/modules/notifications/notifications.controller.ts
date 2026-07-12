import {
  Controller,
  Get,
  Patch,
  Post,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationsService } from './notifications.service';
import { FcmService } from './fcm.service';
import { UserEngagementService } from './user-engagement.service';

// ── DTOs ─────────────────────────────────────────────────────────────

class RegisterFcmTokenDto {
  token!: string;
  deviceType?: string; // android, ios, web
}

class RemoveFcmTokenDto {
  token!: string;
}

// P1.3: DTO for smart notification timing opt-in toggle
class NotificationTimingOptInDto {
  optIn!: boolean;
}

// ── Controller ───────────────────────────────────────────────────────

@Controller('notifications')
@UseGuards(JwtAuthGuard)
export class NotificationsController {
  constructor(
    private readonly notificationsService: NotificationsService,
    private readonly fcmService: FcmService,
    private readonly userEngagementService: UserEngagementService,
    private readonly prisma: PrismaService,
  ) {}

  // ── Existing notification endpoints ────────────────────────────────

  @Get()
  async list(
    @CurrentUser('id') userId: string,
    @Query('limit') limit?: string,
    @Query('unread') unread?: string,
    @Query('page') page?: string,
  ) {
    return this.notificationsService.listForUser(
      userId,
      limit ? parseInt(limit, 10) : 30,
      unread === 'true',
      page ? parseInt(page, 10) : 1,
    );
  }

  @Get('unread-count')
  async unreadCount(@CurrentUser('id') userId: string) {
    const count = await this.notificationsService.getUnreadCount(userId);
    return { count };
  }

  @Patch(':id/read')
  async markRead(
    @Param('id') id: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.notificationsService.markRead(id, userId);
  }

  @Post('mark-all-read')
  async markAllRead(@CurrentUser('id') userId: string) {
    return this.notificationsService.markAllRead(userId);
  }

  // ── FCM Token Management ───────────────────────────────────────────

  /**
   * POST /api/notifications/fcm-token
   * Register or update an FCM token for the authenticated user.
   *
   * The Flutter app calls this after obtaining a token from
   * FirebaseMessaging.instance.getToken().
   *
   * Body: { token: string, deviceType?: string }
   */
  @Post('fcm-token')
  async registerFcmToken(
    @CurrentUser('id') userId: string,
    @Body() dto: RegisterFcmTokenDto,
  ) {
    const result = await this.fcmService.registerToken(
      userId,
      dto.token,
      dto.deviceType || 'unknown',
    );
    return {
      success: true,
      message: 'FCM token registered successfully',
      id: result.id,
    };
  }

  /**
   * DELETE /api/notifications/fcm-token
   * Remove an FCM token (typically called on sign-out).
   *
   * Body: { token: string }
   */
  @Delete('fcm-token')
  async removeFcmToken(@Body() dto: RemoveFcmTokenDto) {
    const removed = await this.fcmService.removeToken(dto.token);
    return {
      success: true,
      removed,
      message: removed
        ? 'FCM token removed successfully'
        : 'FCM token not found',
    };
  }

  // ── P1.3: Smart notification timing opt-in ──────────────────────────

  /**
   * GET /api/notifications/timing-opt-in
   * Returns the user's current smart notification timing opt-in status.
   */
  @Get('timing-opt-in')
  async getTimingOptIn(@CurrentUser('id') userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { notificationTimingOptIn: true },
    });
    return { optIn: user?.notificationTimingOptIn ?? false };
  }

  /**
   * PATCH /api/notifications/timing-opt-in
   * Toggles smart notification timing opt-in.
   * When opting OUT, deletes the user's engagement histogram (right to delete).
   */
  @Patch('timing-opt-in')
  async setTimingOptIn(
    @CurrentUser('id') userId: string,
    @Body() dto: NotificationTimingOptInDto,
  ) {
    await this.prisma.user.update({
      where: { id: userId },
      data: { notificationTimingOptIn: dto.optIn },
    });

    // P1.3: When opting OUT, delete the engagement histogram.
    // This is the "right to delete" per GDPR-aligned behavioral data.
    if (!dto.optIn) {
      await this.userEngagementService.deleteEngagementProfile(userId);
    }

    return {
      success: true,
      optIn: dto.optIn,
      message: dto.optIn
        ? 'Smart notification timing enabled. Kinrel will learn your active hours.'
        : 'Smart notification timing disabled. Your learned data has been deleted.',
    };
  }

  /**
   * GET /api/notifications/engagement-profile
   * P1.3: Transparency — returns the user's engagement histogram so they
   * can see exactly what the ML has learned.
   */
  @Get('engagement-profile')
  async getEngagementProfile(@CurrentUser('id') userId: string) {
    const profile = await this.userEngagementService.getEngagementProfile(userId);
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { notificationTimingOptIn: true },
    });
    return {
      optedIn: user?.notificationTimingOptIn ?? false,
      profile, // null if no profile exists
    };
  }

  /**
   * DELETE /api/notifications/engagement-profile
   * P1.3: Reset — deletes the user's engagement histogram.
   * The user keeps their opt-in status; the histogram is rebuilt from scratch.
   */
  @Delete('engagement-profile')
  async resetEngagementProfile(@CurrentUser('id') userId: string) {
    await this.userEngagementService.deleteEngagementProfile(userId);
    return {
      success: true,
      message: 'Your engagement profile has been reset.',
    };
  }
}
