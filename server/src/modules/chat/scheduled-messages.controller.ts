// server/src/modules/chat/scheduled-messages.controller.ts
//
// DAXELO KINREL — Tier 1 Feature 1.2: Scheduled Messages — Controller
//
// REST endpoints for scheduling / listing / cancelling scheduled
// messages. The dispatcher is server-driven (no HTTP endpoint — it
// fires via the @Cron decorator in ScheduledMessagesService).

import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  UseGuards,
  NotFoundException,
} from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { ScheduledMessagesService } from './scheduled-messages.service';
import { ScheduleMessageDto } from './dto/scheduled-message.dto';

@Controller('chat/scheduled')
@UseGuards(JwtAuthGuard)
export class ScheduledMessagesController {
  constructor(private readonly service: ScheduledMessagesService) {}

  /**
   * POST /chat/scheduled
   * Schedule a new message to be sent at a future time.
   * Body: ScheduleMessageDto.
   */
  @Post()
  async schedule(
    @CurrentUser('id') userId: string,
    @Body() body: ScheduleMessageDto,
  ) {
    return this.service.scheduleMessage(userId, body);
  }

  /**
   * GET /chat/scheduled
   * List the caller's pending + failed scheduled messages.
   */
  @Get()
  async list(@CurrentUser('id') userId: string) {
    return this.service.listMyScheduledMessages(userId);
  }

  /**
   * GET /chat/scheduled/:id
   * Get a single scheduled message by ID (must be owned by the caller).
   */
  @Get(':id')
  async get(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ) {
    try {
      return await this.service.getScheduledMessage(userId, id);
    } catch {
      throw new NotFoundException('Scheduled message not found');
    }
  }

  /**
   * DELETE /chat/scheduled/:id
   * Cancel a pending scheduled message (only pending rows can be cancelled).
   */
  @Delete(':id')
  async cancel(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ) {
    return this.service.cancelScheduledMessage(userId, id);
  }
}
