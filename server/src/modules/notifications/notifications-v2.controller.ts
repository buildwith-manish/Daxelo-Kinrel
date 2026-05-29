import {
  Controller,
  Get,
  Patch,
  Body,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { NotificationsV2Service } from './notifications-v2.service';

// ── DTOs ───────────────────────────────────────────────────────────────

class MarkAsReadDto {
  notificationIds!: string[];
}

class UpdatePreferenceDto {
  eventType!: string;
  push?: boolean;
  inApp?: boolean;
  email?: boolean;
  whatsapp?: boolean;
  quietHoursStart?: string;
  quietHoursEnd?: string;
  quietHoursTimezone?: string;
  maxPerDay?: number;
  digestMode?: string;
}

// ── Controller ─────────────────────────────────────────────────────────

@Controller('notifications/v2')
@UseGuards(JwtAuthGuard)
export class NotificationsV2Controller {
  constructor(private readonly notificationsV2Service: NotificationsV2Service) {}

  /**
   * GET /notifications/v2
   * Get user notifications with pagination.
   *
   * Query params:
   *   page  — page number (default: 1)
   *   limit — items per page (default: 20, max: 100)
   */
  @Get()
  async getUserNotifications(
    @CurrentUser('id') userId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const parsedPage = page ? parseInt(page, 10) : 1;
    const parsedLimit = limit ? parseInt(limit, 10) : 20;

    return this.notificationsV2Service.getUserNotifications(
      userId,
      isNaN(parsedPage) ? 1 : parsedPage,
      isNaN(parsedLimit) ? 20 : parsedLimit,
    );
  }

  /**
   * GET /notifications/v2/unread
   * Get unread notification count for the authenticated user.
   */
  @Get('unread')
  async getUnreadCount(@CurrentUser('id') userId: string) {
    const count = await this.notificationsV2Service.getUnreadCount(userId);
    return { count };
  }

  /**
   * PATCH /notifications/v2/read
   * Mark specific notifications as read.
   *
   * Body: { notificationIds: string[] }
   */
  @Patch('read')
  @HttpCode(HttpStatus.OK)
  async markAsRead(
    @CurrentUser('id') userId: string,
    @Body() dto: MarkAsReadDto,
  ) {
    if (!dto.notificationIds || !Array.isArray(dto.notificationIds)) {
      return {
        success: false,
        message: 'notificationIds must be an array of strings',
      };
    }

    // Filter out any non-string or empty values
    const validIds = dto.notificationIds.filter(
      (id) => typeof id === 'string' && id.trim().length > 0,
    );

    if (validIds.length === 0) {
      return {
        success: true,
        message: 'No valid notification IDs provided',
        updated: 0,
      };
    }

    await this.notificationsV2Service.markAsRead(userId, validIds);

    return {
      success: true,
      message: `${validIds.length} notification(s) marked as read`,
      updated: validIds.length,
    };
  }

  /**
   * PATCH /notifications/v2/read-all
   * Mark all notifications as read for the authenticated user.
   */
  @Patch('read-all')
  @HttpCode(HttpStatus.OK)
  async markAllAsRead(@CurrentUser('id') userId: string) {
    await this.notificationsV2Service.markAllAsRead(userId);

    return {
      success: true,
      message: 'All notifications marked as read',
    };
  }

  /**
   * GET /notifications/v2/preferences
   * Get notification preferences for the authenticated user.
   *
   * Returns all event-type preferences with channel toggles,
   * quiet hours, and digest mode settings.
   */
  @Get('preferences')
  async getPreferences(@CurrentUser('id') userId: string) {
    const preferences = await this.notificationsV2Service.getUserPreferences(userId);

    return {
      success: true,
      preferences,
    };
  }

  /**
   * PATCH /notifications/v2/preferences
   * Update notification preferences for a specific event type.
   *
   * Body: {
   *   eventType: string,
   *   push?: boolean,
   *   inApp?: boolean,
   *   email?: boolean,
   *   whatsapp?: boolean,
   *   quietHoursStart?: string,   // "HH:MM" 24h format
   *   quietHoursEnd?: string,     // "HH:MM" 24h format
   *   quietHoursTimezone?: string, // IANA timezone, default "Asia/Kolkata"
   *   maxPerDay?: number,         // 0-100
   *   digestMode?: string,        // "immediate" | "hourly" | "daily"
   * }
   */
  @Patch('preferences')
  @HttpCode(HttpStatus.OK)
  async updatePreference(
    @CurrentUser('id') userId: string,
    @Body() dto: UpdatePreferenceDto,
  ) {
    if (!dto.eventType || typeof dto.eventType !== 'string') {
      return {
        success: false,
        message: 'eventType is required and must be a string',
      };
    }

    try {
      const updated = await this.notificationsV2Service.updatePreference(
        userId,
        dto.eventType,
        {
          push: dto.push,
          inApp: dto.inApp,
          email: dto.email,
          whatsapp: dto.whatsapp,
          quietHoursStart: dto.quietHoursStart,
          quietHoursEnd: dto.quietHoursEnd,
          quietHoursTimezone: dto.quietHoursTimezone,
          maxPerDay: dto.maxPerDay,
          digestMode: dto.digestMode,
        },
      );

      return {
        success: true,
        message: `Preferences updated for "${dto.eventType}"`,
        preference: updated,
      };
    } catch (error: any) {
      return {
        success: false,
        message: error?.message || 'Failed to update preferences',
      };
    }
  }
}
