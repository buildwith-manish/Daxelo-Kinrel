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
import { NotificationsService } from './notifications.service';
import { FcmService } from './fcm.service';

// ── DTOs ─────────────────────────────────────────────────────────────

class RegisterFcmTokenDto {
  token!: string;
  deviceType?: string; // android, ios, web
}

class RemoveFcmTokenDto {
  token!: string;
}

// ── Controller ───────────────────────────────────────────────────────

@Controller('notifications')
@UseGuards(JwtAuthGuard)
export class NotificationsController {
  constructor(
    private readonly notificationsService: NotificationsService,
    private readonly fcmService: FcmService,
  ) {}

  // ── Existing notification endpoints ────────────────────────────────

  @Get()
  async list(
    @CurrentUser('id') userId: string,
    @Query('limit') limit?: string,
    @Query('unread') unread?: string,
  ) {
    return this.notificationsService.listForUser(
      userId,
      limit ? parseInt(limit, 10) : 30,
      unread === 'true',
    );
  }

  @Get('unread-count')
  async unreadCount(@CurrentUser('id') userId: string) {
    const count = await this.notificationsService.getUnreadCount(userId);
    return { count };
  }

  @Patch(':id/read')
  async markRead(@Param('id') id: string) {
    return this.notificationsService.markRead(id);
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
}
