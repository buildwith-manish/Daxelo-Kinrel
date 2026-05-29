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
import { InvitationsV2Service } from './invitations-v2.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import {
  CreateFamilyIdInviteDto,
  CreateQrCodeInviteDto,
  CreateLinkInviteDto,
  AcceptInviteDto,
} from './dto/invitation-v2.dto';

// ── Controller ─────────────────────────────────────────────────────

@Controller('invitations/v2')
@UseGuards(JwtAuthGuard)
export class InvitationsV2Controller {
  constructor(private readonly invitationsV2Service: InvitationsV2Service) {}

  // ── Create Family ID Invite ──────────────────────────────────────

  /**
   * POST /invitations/v2/family-id
   * Create an invitation via Family ID.
   * The invitee can join by entering the Family ID (e.g. KIN-AB12CD34).
   */
  @Post('family-id')
  @HttpCode(HttpStatus.CREATED)
  async createFamilyIdInvite(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateFamilyIdInviteDto,
  ) {
    return this.invitationsV2Service.createFamilyIdInvite(
      dto.familyId,
      userId,
      dto.role,
    );
  }

  // ── Create QR Code Invite ────────────────────────────────────────

  /**
   * POST /invitations/v2/qr-code
   * Create an invitation via QR Code.
   * Returns QR code data containing a deep link URL.
   */
  @Post('qr-code')
  @HttpCode(HttpStatus.CREATED)
  async createQrCodeInvite(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateQrCodeInviteDto,
  ) {
    return this.invitationsV2Service.createQrCodeInvite(
      dto.familyId,
      userId,
      {
        expiresIn: dto.expiresIn ? this.parseExpiryDays(dto.expiresIn) : undefined,
        maxUses: dto.maxUses,
        preFilledName: dto.preFilledName,
        role: dto.role,
      },
    );
  }

  // ── Create Link Invite ──────────────────────────────────────────

  /**
   * POST /invitations/v2/link
   * Create a shareable link invitation.
   * Returns a URL that can be shared with the invitee.
   */
  @Post('link')
  @HttpCode(HttpStatus.CREATED)
  async createLinkInvite(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateLinkInviteDto,
  ) {
    return this.invitationsV2Service.createLinkInvite(
      dto.familyId,
      userId,
      {
        expiresIn: dto.expiresIn ? this.parseExpiryDays(dto.expiresIn) : undefined,
        maxUses: dto.maxUses,
        preFilledName: dto.preFilledName,
        suggestedRelation: dto.suggestedRelation,
        role: dto.role,
      },
    );
  }

  // ── Accept Invite ───────────────────────────────────────────────

  /**
   * POST /invitations/v2/accept
   * Accept an invitation using an invite code or token.
   * Creates FamilyMember + Person records.
   * Handles idempotency: if user is already a member, returns existing membership.
   */
  @Post('accept')
  @HttpCode(HttpStatus.OK)
  async acceptInvite(
    @CurrentUser('id') userId: string,
    @Body() dto: AcceptInviteDto,
  ) {
    return this.invitationsV2Service.acceptInvite(
      dto.inviteCodeOrToken,
      userId,
    );
  }

  // ── Reject Invite ───────────────────────────────────────────────

  /**
   * POST /invitations/v2/:id/reject
   * Reject an invitation.
   */
  @Post(':id/reject')
  @HttpCode(HttpStatus.OK)
  async rejectInvite(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ) {
    await this.invitationsV2Service.rejectInvite(id, userId);
    return { rejected: true, id };
  }

  // ── Get Pending Invitations ─────────────────────────────────────

  /**
   * GET /invitations/v2/pending
   * Get all pending invitations for the current user.
   */
  @Get('pending')
  async getPendingInvitations(@CurrentUser('id') userId: string) {
    return this.invitationsV2Service.getPendingInvitations(userId);
  }

  // ── Get Family Invitations ──────────────────────────────────────

  /**
   * GET /invitations/v2/family/:id
   * Get all invitations for a family (admin/owner only).
   */
  @Get('family/:id')
  async getFamilyInvitations(
    @CurrentUser('id') userId: string,
    @Param('id') familyId: string,
  ) {
    return this.invitationsV2Service.getFamilyInvitations(familyId, userId);
  }

  // ── Revoke Invite ───────────────────────────────────────────────

  /**
   * DELETE /invitations/v2/:id
   * Revoke an invitation.
   * Only the inviter or a family admin can revoke.
   */
  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  async revokeInvite(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ) {
    await this.invitationsV2Service.revokeInvite(id, userId);
    return { revoked: true, id };
  }

  // ── Private Helpers ─────────────────────────────────────────────

  /**
   * Parse expiry string to number of days.
   * Accepts formats: "7d", "7", ISO date string.
   * Defaults to 7 days if unparseable.
   */
  private parseExpiryDays(expiresIn: string): number {
    // Try "7d" format
    const daysMatch = expiresIn.match(/^(\d+)d$/);
    if (daysMatch) {
      return parseInt(daysMatch[1], 10);
    }

    // Try plain number
    const asNumber = parseInt(expiresIn, 10);
    if (!isNaN(asNumber) && asNumber > 0) {
      return asNumber;
    }

    // Try ISO date string — compute days from now
    const asDate = new Date(expiresIn);
    if (!isNaN(asDate.getTime()) && asDate.getTime() > Date.now()) {
      const diffMs = asDate.getTime() - Date.now();
      return Math.max(1, Math.ceil(diffMs / (1000 * 60 * 60 * 24)));
    }

    // Fallback
    return 7;
  }
}
