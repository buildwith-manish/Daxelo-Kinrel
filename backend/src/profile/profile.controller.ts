import {
  Controller,
  Get,
  Post,
  Put,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  Req,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ProfileService } from './profile.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { UpdateProfileDto } from './dto/update-profile.dto';
import { UpdateAvatarDto } from './dto/update-avatar.dto';
import { ChangePasswordDto } from './dto/change-password.dto';
import { LinkGoogleDto } from './dto/link-google.dto';
import { UpdateUsernameDto } from './dto/update-username.dto';
import { Verify2faDto, Disable2faDto } from './dto/two-factor.dto';
import { DeleteAccountDto } from './dto/delete-account.dto';
import { ExportFamilyDto } from './dto/export-family.dto';
import { CreateSupportTicketDto } from './dto/create-support-ticket.dto';
import { QuietHoursDto } from './dto/quiet-hours.dto';
import { CheckUsernameDto } from './dto/check-username.dto';
import * as CryptoJS from 'crypto-js';

@Controller()
export class ProfileController {
  constructor(private profileService: ProfileService) {}

  // ── User Stats ──────────────────────────────────────────────────────

  @Get('users/me/stats')
  @UseGuards(JwtAuthGuard)
  async getUserStats(@CurrentUser('id') userId: string) {
    return this.profileService.getUserStats(userId);
  }

  // ── Avatar ──────────────────────────────────────────────────────────

  @Put('users/me/avatar')
  @UseGuards(JwtAuthGuard)
  async updateAvatar(
    @CurrentUser('id') userId: string,
    @Body() dto: UpdateAvatarDto,
  ) {
    return this.profileService.updateAvatar(userId, dto.imageUrl);
  }

  // ── Profile Update ──────────────────────────────────────────────────

  @Patch('users/me')
  @UseGuards(JwtAuthGuard)
  async updateProfile(
    @CurrentUser('id') userId: string,
    @Body() dto: UpdateProfileDto,
  ) {
    return this.profileService.updateProfile(userId, dto);
  }

  // ── Change Password ─────────────────────────────────────────────────

  @Post('auth/change-password')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async changePassword(
    @CurrentUser('id') userId: string,
    @Body() dto: ChangePasswordDto,
  ) {
    return this.profileService.changePassword(userId, dto);
  }

  // ── Google Link / Unlink ────────────────────────────────────────────

  @Post('auth/link-google')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async linkGoogle(
    @CurrentUser('id') userId: string,
    @Body() dto: LinkGoogleDto,
  ) {
    return this.profileService.linkGoogle(userId, dto.googleToken);
  }

  @Delete('auth/unlink-google')
  @UseGuards(JwtAuthGuard)
  async unlinkGoogle(@CurrentUser('id') userId: string) {
    return this.profileService.unlinkGoogle(userId);
  }

  // ── 2FA Setup / Verify / Disable ───────────────────────────────────

  @Post('auth/2fa/setup')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async setup2fa(@CurrentUser('id') userId: string) {
    return this.profileService.setup2fa(userId);
  }

  @Post('auth/2fa/verify')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async verify2fa(
    @CurrentUser('id') userId: string,
    @Body() dto: Verify2faDto,
  ) {
    return this.profileService.verify2fa(userId, dto);
  }

  @Delete('auth/2fa')
  @UseGuards(JwtAuthGuard)
  async disable2fa(
    @CurrentUser('id') userId: string,
    @Body() dto: Disable2faDto,
  ) {
    return this.profileService.disable2fa(userId, dto);
  }

  // ── Sessions ────────────────────────────────────────────────────────

  @Get('auth/sessions')
  @UseGuards(JwtAuthGuard)
  async getSessions(@CurrentUser('id') userId: string) {
    return this.profileService.getSessions(userId);
  }

  @Delete('auth/sessions/:sessionId')
  @UseGuards(JwtAuthGuard)
  async revokeSession(
    @CurrentUser('id') userId: string,
    @Param('sessionId') sessionId: string,
  ) {
    return this.profileService.revokeSession(userId, sessionId);
  }

  @Delete('auth/sessions/all-except-current')
  @UseGuards(JwtAuthGuard)
  async revokeAllOtherSessions(
    @CurrentUser('id') userId: string,
    @Req() req: any,
  ) {
    // Hash the current JWT token to identify the current session
    const authHeader = req.headers['authorization'] as string;
    const token = authHeader?.replace('Bearer ', '') ?? '';
    const currentTokenHash = CryptoJS.SHA256(token).toString();

    return this.profileService.revokeAllOtherSessions(userId, currentTokenHash);
  }

  // ── Data Export ─────────────────────────────────────────────────────

  @Post('users/me/data-export')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async requestDataExport(@CurrentUser('id') userId: string) {
    return this.profileService.requestDataExport(userId);
  }

  // ── Delete Account ──────────────────────────────────────────────────

  @Delete('users/me')
  @UseGuards(JwtAuthGuard)
  async deleteAccount(
    @CurrentUser('id') userId: string,
    @Body() dto: DeleteAccountDto,
  ) {
    return this.profileService.deleteAccount(userId, dto);
  }

  // ── User Families ───────────────────────────────────────────────────

  @Get('users/me/families')
  @UseGuards(JwtAuthGuard)
  async getUserFamilies(@CurrentUser('id') userId: string) {
    return this.profileService.getUserFamilies(userId);
  }

  // ── Invitations ─────────────────────────────────────────────────────

  @Get('users/me/invitations')
  @UseGuards(JwtAuthGuard)
  async getUserInvitations(@CurrentUser('id') userId: string) {
    return this.profileService.getUserInvitations(userId);
  }

  @Post('invitations/:id/accept')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async acceptInvitation(
    @CurrentUser('id') userId: string,
    @Param('id') invitationId: string,
  ) {
    return this.profileService.acceptInvitation(userId, invitationId);
  }

  @Post('invitations/:id/decline')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async declineInvitation(
    @CurrentUser('id') userId: string,
    @Param('id') invitationId: string,
  ) {
    return this.profileService.declineInvitation(userId, invitationId);
  }

  // ── Blocked Users ───────────────────────────────────────────────────

  @Get('users/me/blocked')
  @UseGuards(JwtAuthGuard)
  async getBlockedUsers(@CurrentUser('id') userId: string) {
    return this.profileService.getBlockedUsers(userId);
  }

  @Delete('users/me/blocked/:userId')
  @UseGuards(JwtAuthGuard)
  async unblockUser(
    @CurrentUser('id') currentUserId: string,
    @Param('userId') targetUserId: string,
  ) {
    return this.profileService.unblockUser(currentUserId, targetUserId);
  }

  // ── Family Export ───────────────────────────────────────────────────

  @Post('families/:familyId/export')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async exportFamily(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() dto: ExportFamilyDto,
  ) {
    return this.profileService.exportFamily(userId, familyId, dto);
  }

  // ── Support Ticket ──────────────────────────────────────────────────

  @Post('support/tickets')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.CREATED)
  async createSupportTicket(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateSupportTicketDto,
  ) {
    return this.profileService.createSupportTicket(userId, dto);
  }

  // ── Logout ──────────────────────────────────────────────────────────

  @Post('auth/logout')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async logout(
    @CurrentUser('id') userId: string,
    @Req() req: any,
  ) {
    // Hash the current JWT token to identify the session
    const authHeader = req.headers['authorization'] as string;
    const token = authHeader?.replace('Bearer ', '') ?? '';
    const tokenHash = CryptoJS.SHA256(token).toString();

    return this.profileService.logout(userId, tokenHash);
  }

  // ── Quiet Hours ─────────────────────────────────────────────────────

  @Put('users/me/quiet-hours')
  @UseGuards(JwtAuthGuard)
  async updateQuietHours(
    @CurrentUser('id') userId: string,
    @Body() dto: QuietHoursDto,
  ) {
    return this.profileService.updateQuietHours(userId, dto);
  }

  // ── Check Username ──────────────────────────────────────────────────

  @Get('users/check-username')
  async checkUsername(@Query() query: CheckUsernameDto) {
    return this.profileService.checkUsername(query.username);
  }

  // ── Update Username ─────────────────────────────────────────────────

  @Patch('users/me/username')
  @UseGuards(JwtAuthGuard)
  async updateUsername(
    @CurrentUser('id') userId: string,
    @Body() dto: UpdateUsernameDto,
  ) {
    return this.profileService.updateUsername(userId, dto);
  }
}
