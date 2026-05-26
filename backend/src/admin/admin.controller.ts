import { Controller, Get, Post, Patch, Put, Param, Query, Body, UseGuards } from '@nestjs/common';
import { AdminService } from './admin.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ListUsersDto } from './dto/list-users.dto';
import { CreateRuleDto } from './dto/create-rule.dto';
import { UpdateRuleDto } from './dto/update-rule.dto';
import { CreateTemplateDto } from './dto/create-template.dto';
import { UpdateTemplateDto } from './dto/update-template.dto';

@Controller('admin')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('admin')
export class AdminController {
  constructor(private adminService: AdminService) {}

  /** GET /api/admin — Dashboard stats */
  @Get()
  async getDashboardStats() {
    return this.adminService.getDashboardStats();
  }

  /** GET /api/admin/users — List all users */
  @Get('users')
  async listUsers(@Query() dto: ListUsersDto) {
    return this.adminService.listUsers(dto);
  }

  /** GET /api/admin/moderation/rules — List rules */
  @Get('moderation/rules')
  async listRules() {
    return this.adminService.listRules();
  }

  /** POST /api/admin/moderation/rules — Create rule */
  @Post('moderation/rules')
  async createRule(
    @Body() dto: CreateRuleDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.adminService.createRule(dto, user.id);
  }

  /** PATCH /api/admin/moderation/rules/:id — Update rule */
  @Patch('moderation/rules/:id')
  async updateRule(
    @Param('id') id: string,
    @Body() dto: UpdateRuleDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.adminService.updateRule(id, dto, user.id);
  }

  /** GET /api/admin/moderation/stats — Moderation dashboard stats */
  @Get('moderation/stats')
  async getModerationStats() {
    return this.adminService.getModerationStats();
  }

  /** GET /api/admin/sla/report — SLA report */
  @Get('sla/report')
  async getSlaReport(@Query('month') month?: string) {
    return this.adminService.getSlaReport(month);
  }

  /** GET /api/admin/whatsapp/templates — List templates */
  @Get('whatsapp/templates')
  async listTemplates(@Query('status') status?: string) {
    return this.adminService.listTemplates(status);
  }

  /** POST /api/admin/whatsapp/templates — Create template */
  @Post('whatsapp/templates')
  async createTemplate(@Body() dto: CreateTemplateDto) {
    return this.adminService.createTemplate(dto);
  }

  /** PUT /api/admin/whatsapp/templates/:id — Update template */
  @Put('whatsapp/templates/:id')
  async updateTemplate(
    @Param('id') id: string,
    @Body() dto: UpdateTemplateDto,
  ) {
    return this.adminService.updateTemplate(id, dto);
  }

  /** GET /api/admin/kb/analytics — KB analytics */
  @Get('kb/analytics')
  async getKbAnalytics(@Query('days') days?: string) {
    return this.adminService.getKbAnalytics(days ? parseInt(days, 10) : 30);
  }
}
