import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { InvitationsService } from './invitations.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { CreateInvitationDto } from './dto/create-invitation.dto';

@Controller('invitations')
@UseGuards(JwtAuthGuard)
export class InvitationsController {
  constructor(private readonly invitationsService: InvitationsService) {}

  /**
   * GET /api/invitations?familyId=xxx
   * List invitations for a family.
   */
  @Get()
  async findByFamily(
    @CurrentUser('id') userId: string,
    @Query('familyId') familyId: string,
  ) {
    if (!familyId) {
      return [];
    }
    return this.invitationsService.findByFamily(familyId, userId);
  }

  /**
   * POST /api/invitations
   * Create a new invitation.
   */
  @Post()
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @HttpCode(HttpStatus.CREATED)
  async create(
    @CurrentUser('id') userId: string,
    @Body() body: CreateInvitationDto,
  ) {
    return this.invitationsService.create(userId, {
      familyId: body.familyId,
      inviterId: userId,  // Always use authenticated user's ID — prevent spoofing
      recipientEmail: body.recipientEmail,
      recipientPhone: body.recipientPhone,
      recipientName: body.recipientName,
      role: body.role,
      channel: body.channel,
    });
  }

  /**
   * POST /api/invitations/:id/accept
   * Accept an invitation (Flutter app endpoint).
   */
  @Post(':id/accept')
  @HttpCode(HttpStatus.OK)
  async accept(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ) {
    return this.invitationsService.acceptById(id, userId);
  }

  /**
   * POST /api/invitations/:id/decline
   * Decline an invitation (Flutter app endpoint).
   */
  @Post(':id/decline')
  @HttpCode(HttpStatus.OK)
  async decline(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ) {
    return this.invitationsService.declineById(id, userId);
  }

  /**
   * PATCH /api/invitations
   * Accept invitation by token.
   */
  @Patch()
  async acceptByToken(
    @CurrentUser('id') userId: string,
    @Body() body: { token: string },
  ) {
    return this.invitationsService.acceptByToken(body.token, userId);
  }

  /**
   * DELETE /api/invitations?id=xxx
   * Cancel an invitation.
   */
  @Delete()
  @HttpCode(HttpStatus.OK)
  async cancel(
    @CurrentUser('id') userId: string,
    @Query('id') id: string,
  ) {
    return this.invitationsService.cancel(id, userId);
  }
}
