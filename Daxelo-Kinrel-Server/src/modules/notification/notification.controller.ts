import {
  Controller,
  Get,
  Post,
  Put,
  Patch,
  Body,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { DualAuthGuard } from '@/common/guards/dual-auth.guard';
import { CurrentUser } from '@/common/decorators/current-user.decorator';
import { NotificationService } from './notification.service';
import { CreateNotificationDto } from './dto/create-notification.dto';
import { UpdatePreferenceDto } from './dto/update-preference.dto';
import { MarkReadDto } from './dto/mark-read.dto';

/**
 * NotificationController — /api/notifications
 *
 * Handles:
 * - GET    /api/notifications      — List notifications
 * - PATCH  /api/notifications      — Mark as read
 * - PUT    /api/notifications      — Update notification preferences
 * - POST   /api/notifications      — Create notification
 */
@Controller('notifications')
@UseGuards(DualAuthGuard)
export class NotificationController {
  private readonly logger = new Logger(NotificationController.name);

  constructor(private readonly notificationService: NotificationService) {}

  // ── GET /api/notifications ───────────────────────────────────────
  @Get()
  async listNotifications(
    @CurrentUser('id') userId?: string,
    @Query('read') read?: string,
    @Query('limit') limit?: string,
    @Query('offset') offset?: string,
  ) {
    return this.notificationService.listNotifications({
      userId: userId ?? '',
      read,
      limit: limit ? parseInt(limit, 10) : undefined,
      offset: offset ? parseInt(offset, 10) : undefined,
    });
  }

  // ── PATCH /api/notifications ─────────────────────────────────────
  @Patch()
  async markAsRead(@Body() dto: MarkReadDto) {
    return this.notificationService.markAsRead(dto);
  }

  // ── PUT /api/notifications ──────────────────────────────────────
  @Put()
  async updatePreference(@Body() dto: UpdatePreferenceDto) {
    return this.notificationService.updatePreference(dto);
  }

  // ── POST /api/notifications ─────────────────────────────────────
  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createNotification(@Body() dto: CreateNotificationDto) {
    return this.notificationService.createNotification(dto);
  }
}
