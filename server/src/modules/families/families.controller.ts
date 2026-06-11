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
import { Public } from '../../common/decorators/public.decorator';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { PaginationDto } from '../../common/dto/pagination.dto';
import { CreateFamilyDto } from './dto/create-family.dto';
import { UpdateFamilyDto } from './dto/update-family.dto';
import { GenerateInviteDto, JoinByTokenDto } from './dto/join-family.dto';

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

  @Get(':familyId/members')
  @ApiOperation({ summary: 'Get all members of a family with user profiles' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns list of family members' })
  async getMembers(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.familiesService.getMembers(userId, familyId);
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
  @ApiOperation({ summary: 'Permanently delete a family (only archived families, admin only)' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Family permanently deleted' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Family not found' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Insufficient permissions — admin role required' })
  async permanentDelete(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    // FIXED: Require admin role — any member could previously permanently
    // delete all family data. Now only admins can perform this destructive action.
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

  // ── Social System: Family Invite Endpoints ─────────────────────────────

  @Post(':familyId/invite')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Generate an invite link for a family (owner/admin only)' })
  async generateInvite(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() dto: GenerateInviteDto,
  ) {
    return this.familiesService.generateInvite(userId, familyId, dto);
  }

  @Post(':familyId/invite/revoke')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Revoke all active invite links for a family (owner only)' })
  async revokeInvites(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.familiesService.revokeInvites(userId, familyId);
  }

  @Get('invite/preview/:token')
  @Public()
  @ApiOperation({ summary: 'Preview a family from an invite token (no auth required)' })
  async previewInvite(@Param('token') token: string) {
    return this.familiesService.previewInvite(token);
  }

  @Post('invite/join')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Join a family using an invite token' })
  async joinFamily(
    @CurrentUser('id') userId: string,
    @Body() dto: JoinByTokenDto,
  ) {
    return this.familiesService.joinFamily(userId, dto.token);
  }

  // ── Member Management Endpoints ──────────────────────────────────────

  @Patch(':familyId/members/:memberId/role')
  @ApiOperation({ summary: 'Update a member role in the family (admin only)' })
  async updateMemberRole(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('memberId') memberId: string,
    @Body() body: { role: string },
  ) {
    return this.familiesService.updateMemberRole(userId, familyId, memberId, body.role);
  }

  @Delete(':familyId/members/:memberId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Remove a member from the family (admin only)' })
  async removeMember(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('memberId') memberId: string,
  ) {
    return this.familiesService.removeMember(userId, familyId, memberId);
  }

  @Patch(':familyId/visibility')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Toggle family public/private visibility (owner only)' })
  async toggleVisibility(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() body: { isPublic: boolean },
  ) {
    return this.familiesService.toggleVisibility(userId, familyId, body.isPublic);
  }
}
