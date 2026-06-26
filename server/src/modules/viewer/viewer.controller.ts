/**
 * ViewerController — v2.2 Viewer-Driven Relationship Engine
 * ═══════════════════════════════════════════════════════════════════════
 *
 * Exposes the viewer resolution + person-link lifecycle endpoints.
 *
 * Endpoints (per architecture §16):
 *   GET    /families/:familyId/viewer
 *   POST   /families/:familyId/persons/:personId/claim
 *   DELETE /families/:familyId/persons/:personId/unlink
 *   POST   /families/:familyId/persons/:personId/invite
 *   POST   /families/:familyId/invitations/:code/accept
 *
 * Note: The `claim`, `unlink`, `invite`, and `accept` endpoints are mounted
 * here rather than in MembersController so the viewer module owns the
 * complete person-link lifecycle in one place. The MembersController still
 * owns CRUD over Person nodes.
 */

import {
  Controller,
  Get,
  Post,
  Delete,
  Body,
  Param,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ViewerService } from './viewer.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { InvitePersonDto } from '../members/dto/invite-person.dto';

@Controller('families/:familyId')
@UseGuards(JwtAuthGuard)
export class ViewerController {
  constructor(private readonly viewerService: ViewerService) {}

  /**
   * GET /families/:familyId/viewer
   * Returns the viewer Person ID for the current user.
   */
  @Get('viewer')
  async getViewer(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.viewerService.resolveViewer(userId, familyId);
  }

  /**
   * POST /families/:familyId/persons/:personId/claim
   * Links the authenticated user to the Person node.
   */
  @Post('persons/:personId/claim')
  @HttpCode(HttpStatus.OK)
  async claim(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
  ) {
    return this.viewerService.claimPerson(userId, familyId, personId);
  }

  /**
   * DELETE /families/:familyId/persons/:personId/unlink
   * Removes the link between the authenticated user and the Person node.
   */
  @Delete('persons/:personId/unlink')
  @HttpCode(HttpStatus.OK)
  async unlink(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
  ) {
    return this.viewerService.unlinkPerson(userId, familyId, personId);
  }

  /**
   * POST /families/:familyId/persons/:personId/invite
   * Creates a one-time invitation for the target Person.
   */
  @Post('persons/:personId/invite')
  @HttpCode(HttpStatus.CREATED)
  async invite(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
    @Body() dto: InvitePersonDto,
  ) {
    return this.viewerService.invitePerson(userId, familyId, personId, dto);
  }

  /**
   * POST /families/:familyId/invitations/:code/accept
   * Accepts a pending person-link invitation and binds the user.
   */
  @Post('invitations/:code/accept')
  @HttpCode(HttpStatus.OK)
  async acceptInvitation(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('code') code: string,
  ) {
    return this.viewerService.acceptInvitation(userId, familyId, code);
  }
}
