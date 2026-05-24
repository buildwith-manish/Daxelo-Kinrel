import { Controller, Post, Param, Body, HttpCode, HttpStatus } from '@nestjs/common';
import { CommunityService } from './community.service';
import { RsvpDto } from './dto/rsvp.dto';

/**
 * EventController — /api/v1/events/*
 *
 * Routes:
 * - POST /api/v1/events/:eventId/rsvp — RSVP
 */
@Controller('v1/events')
export class EventController {
  constructor(private readonly communityService: CommunityService) {}

  @Post(':eventId/rsvp')
  async rsvp(
    @Param('eventId') eventId: string,
    @Body() dto: RsvpDto,
  ) {
    return this.communityService.rsvp(eventId, dto);
  }
}
