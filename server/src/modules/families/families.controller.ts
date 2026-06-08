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
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { FamiliesService } from './families.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { PaginationDto } from '../../common/dto/pagination.dto';
import { CreateFamilyDto } from './dto/create-family.dto';
import { UpdateFamilyDto } from './dto/update-family.dto';
import { Public } from '../../common/decorators/public.decorator';

@ApiTags('families')
@Controller('families')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class FamiliesController {
  constructor(private familiesService: FamiliesService) {}

  @Get()
  @ApiOperation({ summary: 'Get all active families for the current user' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns paginated list of active families' })
  async findAll(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationDto,
  ) {
    return this.familiesService.findAll(userId, pagination);
  }

  @Get('archived')
  @ApiOperation({ summary: 'Get all archived families for the current user' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns paginated list of archived families with days remaining' })
  async findArchived(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationDto,
  ) {
    return this.familiesService.findArchived(userId, pagination);
  }

  // ── Join Family via Invite Token (preview) ────────────────────────
  // These MUST come before the dynamic :familyId routes to avoid
  // 'join' being captured by :familyId.

  @Get('join/:token')
  @Public()
  @ApiOperation({ summary: 'Preview family info via invite token' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns family preview info' })
  async previewJoinByToken(@Param('token') token: string) {
    return this.familiesService.previewJoinByToken(token);
  }

  @Post('join/:token')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Join family via invite token' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Joined family successfully' })
  @ApiResponse({ status: HttpStatus.GONE, description: 'Invite expired or max uses reached' })
  @ApiResponse({ status: HttpStatus.CONFLICT, description: 'Already a member' })
  async joinByToken(
    @CurrentUser('id') userId: string,
    @Param('token') token: string,
  ) {
    return this.familiesService.joinByToken(userId, token);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a new family' })
  @ApiResponse({ status: HttpStatus.CREATED, description: 'Family created successfully' })
  @ApiResponse({ status: HttpStatus.BAD_REQUEST, description: 'Invalid input data' })
  async create(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateFamilyDto,
  ) {
    return this.familiesService.create(userId, dto);
  }

  @Get(':familyId')
  @ApiOperation({ summary: 'Get a family by ID' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns the family details' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Family not found' })
  async findOne(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.familiesService.findOne(userId, familyId);
  }

  @Patch(':familyId')
  @ApiOperation({ summary: 'Update a family' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Family updated successfully' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Family not found' })
  async update(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() dto: UpdateFamilyDto,
  ) {
    return this.familiesService.update(userId, familyId, dto);
  }

  @Delete(':familyId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Archive a family (soft-delete for 30 days)' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Family archived successfully. Can be restored within 30 days.' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Family not found' })
  async archive(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.familiesService.archive(userId, familyId);
  }

  @Post(':familyId/restore')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Restore an archived family' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Family restored successfully' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Family not found' })
  @ApiResponse({ status: HttpStatus.BAD_REQUEST, description: 'Family is not archived' })
  async restore(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.familiesService.restore(userId, familyId);
  }

  @Delete(':familyId/permanent')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Permanently delete a family (only archived families)' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Family permanently deleted' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Family not found' })
  async permanentDelete(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    // Verify the user is an admin before allowing permanent delete
    await this.familiesService.requireFamilyRole(userId, familyId, 'admin');
    return this.familiesService.permanentDelete(familyId);
  }

  @Delete(':familyId/leave')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Leave a family as a non-admin member' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Left family successfully' })
  @ApiResponse({ status: HttpStatus.BAD_REQUEST, description: 'Cannot leave as the only admin' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Not a member of this family' })
  async leaveFamily(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.familiesService.leaveFamily(userId, familyId);
  }

  // ── Family Invite Endpoints ─────────────────────────────────────

  @Post(':familyId/invite/generate')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Generate an invite link/token (owner/admin only)' })
  @ApiResponse({ status: HttpStatus.CREATED, description: 'Invite generated successfully' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Insufficient permissions' })
  async generateInvite(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() body: { expiresInDays?: number; maxUses?: number },
  ) {
    return this.familiesService.generateInvite(userId, familyId, body);
  }

  @Post(':familyId/invite/revoke')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Revoke all active invite links (owner only)' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Invites revoked successfully' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Insufficient permissions' })
  async revokeInvites(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.familiesService.revokeInvites(userId, familyId);
  }

  // ── Family Privacy ──────────────────────────────────────────────

  @Patch(':familyId/privacy')
  @ApiOperation({ summary: 'Toggle family public/private (owner only)' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Privacy updated successfully' })
  async updatePrivacy(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() body: { isPublic: boolean },
  ) {
    return this.familiesService.updatePrivacy(userId, familyId, body.isPublic);
  }

  // ── Member Management ───────────────────────────────────────────

  @Delete(':familyId/members/leave')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Leave family (non-owner only)' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Left family successfully' })
  async leaveFamilyV2(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.familiesService.leaveFamilyV2(userId, familyId);
  }

  @Delete(':familyId/members/:memberUserId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Remove a family member (admin/owner only)' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Member removed successfully' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Insufficient permissions' })
  async removeMember(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('memberUserId') memberUserId: string,
  ) {
    return this.familiesService.removeMember(userId, familyId, memberUserId);
  }

  @Patch(':familyId/members/:memberUserId/role')
  @ApiOperation({ summary: 'Change member role (owner only)' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Role updated successfully' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Only owner can change roles' })
  async changeMemberRole(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('memberUserId') memberUserId: string,
    @Body() body: { role: string },
  ) {
    return this.familiesService.changeMemberRole(userId, familyId, memberUserId, body.role);
  }

  @Post(':familyId/members/transfer-ownership')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Transfer family ownership to another member' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Ownership transferred successfully' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Only owner can transfer ownership' })
  async transferOwnership(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() body: { newOwnerId: string },
  ) {
    return this.familiesService.transferOwnership(userId, familyId, body.newOwnerId);
  }
}
