import {
  Controller,
  Get,
  Post,
  Patch,
  Body,
  Query,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { InvitationService } from './invitation.service';
import { CreateInvitationDto } from './dto/create-invitation.dto';

/**
 * InvitationController — /api/invitations
 *
 * Routes:
 * - GET   /api/invitations  — List invitations
 * - POST  /api/invitations  — Create invitation
 * - PATCH /api/invitations  — Accept invitation
 */
@Controller('invitations')
export class InvitationController {
  constructor(private readonly invitationService: InvitationService) {}

  @Get()
  async listInvitations(
    @Query('familyId') familyId: string,
    @Query('status') status?: string,
  ) {
    return this.invitationService.listInvitations({
      familyId,
      status: status || undefined,
    });
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createInvitation(@Body() dto: CreateInvitationDto) {
    return this.invitationService.createInvitation(dto);
  }

  @Patch()
  async acceptInvitation(@Body() body: { token: string }) {
    return this.invitationService.acceptInvitation(body.token);
  }
}
