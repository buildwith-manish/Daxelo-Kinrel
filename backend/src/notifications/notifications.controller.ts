import {
  Controller,
  Get,
  Post,
  Patch,
  Put,
  Body,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { NotificationsService } from './notifications.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { GetNotificationsDto } from './dto/get-notifications.dto';
import { MarkReadDto } from './dto/mark-read.dto';
import { UpdatePreferencesDto } from './dto/update-preferences.dto';
import { CreateNotificationDto } from './dto/create-notification.dto';

@Controller('notifications')
export class NotificationsController {
  constructor(private notificationsService: NotificationsService) {}

  /**
   * GET /api/notifications?userId=xxx&read=true|false&limit=20&offset=0
   * Get user's notifications with unread count
   */
  @Get()
  @UseGuards(JwtAuthGuard)
  async getNotifications(@Query() dto: GetNotificationsDto) {
    return this.notificationsService.getNotifications(dto);
  }

  /**
   * PATCH /api/notifications
   * Mark as read: { userId, notificationIds? }
   */
  @Patch()
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async markAsRead(@Body() dto: MarkReadDto) {
    return this.notificationsService.markAsRead(dto);
  }

  /**
   * PUT /api/notifications
   * Update preferences: { userId, eventType, ... }
   */
  @Put()
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async updatePreferences(@Body() dto: UpdatePreferencesDto) {
    return this.notificationsService.updatePreferences(dto);
  }

  /**
   * POST /api/notifications
   * Create and send: { type, actorUserId, targetUserId, ... }
   */
  @Post()
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.CREATED)
  async createNotification(@Body() dto: CreateNotificationDto) {
    return this.notificationsService.createNotification(dto);
  }
}
