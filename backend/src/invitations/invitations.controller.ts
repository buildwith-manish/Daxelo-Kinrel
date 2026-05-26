import {
  Controller,
  Get,
  Post,
  Patch,
  Body,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { InvitationsService } from './invitations.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { GetInvitationsDto } from './dto/get-invitations.dto';
import { CreateInvitationDto } from './dto/create-invitation.dto';
import { AcceptInvitationDto } from './dto/accept-invitation.dto';

@Controller('invitations')
export class InvitationsController {
  constructor(private invitationsService: InvitationsService) {}

  /**
   * GET /api/invitations?familyId=xxx&status=xxx
   * List invitations for a family
   */
  @Get()
  @UseGuards(JwtAuthGuard)
  async getInvitations(@Query() dto: GetInvitationsDto) {
    return this.invitationsService.getInvitations(dto);
  }

  /**
   * POST /api/invitations
   * Create invitation: { familyId, inviterId, ... }
   */
  @Post()
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.CREATED)
  async createInvitation(@Body() dto: CreateInvitationDto) {
    return this.invitationsService.createInvitation(dto);
  }

  /**
   * PATCH /api/invitations
   * Accept invitation: { token }
   */
  @Patch()
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async acceptInvitation(@Body() dto: AcceptInvitationDto) {
    return this.invitationsService.acceptInvitation(dto);
  }
}
