import {
  Controller,
  Get,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AdminService } from './admin.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('admin')
@UseGuards(JwtAuthGuard)
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  /**
   * GET /api/admin
   * Dashboard stats.
   */
  @Get()
  async getDashboardStats(@CurrentUser('role') role: string) {
    return this.adminService.getDashboardStats(role);
  }

  /**
   * GET /api/admin/users
   * User list (paginated, searchable).
   */
  @Get('users')
  async listUsers(
    @CurrentUser('role') role: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('search') search?: string,
  ) {
    return this.adminService.listUsers(
      role,
      page ? parseInt(page, 10) : 1,
      limit ? parseInt(limit, 10) : 20,
      search,
    );
  }

  /**
   * GET /api/admin/sla/report
   * SLA report.
   */
  @Get('sla/report')
  async getSlaReport(@CurrentUser('role') role: string) {
    return this.adminService.getSlaReport(role);
  }

  /**
   * GET /api/admin/kb/analytics
   * KB analytics.
   */
  @Get('kb/analytics')
  async getKbAnalytics(@CurrentUser('role') role: string) {
    return this.adminService.getKbAnalytics(role);
  }

  /**
   * GET /api/admin/whatsapp/templates
   * WhatsApp templates.
   */
  @Get('whatsapp/templates')
  async getWhatsappTemplates(@CurrentUser('role') role: string) {
    return this.adminService.getWhatsappTemplates(role);
  }

  /**
   * GET /api/admin/moderation/stats
   * Moderation stats.
   */
  @Get('moderation/stats')
  async getModerationStats(@CurrentUser('role') role: string) {
    return this.adminService.getModerationStats(role);
  }

  /**
   * GET /api/admin/moderation/rules
   * Moderation rules.
   */
  @Get('moderation/rules')
  async getModerationRules(@CurrentUser('role') role: string) {
    return this.adminService.getModerationRules(role);
  }
}
