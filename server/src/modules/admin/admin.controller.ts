import {
  Controller,
  Get,
  Query,
  UseGuards,
  ForbiddenException,
} from '@nestjs/common';
import { AdminService } from './admin.service';
import { ChatAnalyticsService } from '../analytics/chat-analytics.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('admin')
@UseGuards(JwtAuthGuard)
export class AdminController {
  constructor(
    private readonly adminService: AdminService,
    private readonly analyticsService: ChatAnalyticsService,
  ) {}

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

  // ── Pack 13.3: Chat Analytics ──────────────────────────────────────
  //
  // Admin-only endpoints to query aggregate event counts. Used by
  // product/data teams to measure chat engagement (messages sent,
  // reactions, streaks, etc.) without a dashboard UI — just queryable
  // JSON returned by these endpoints.

  /**
   * GET /api/admin/analytics/events?eventName=X&from=2026-09-01&to=2026-09-30
   * Returns daily aggregate counts per event.
   * Admin-only — non-admin users get 403.
   */
  @Get('analytics/events')
  async getAnalyticsEvents(
    @CurrentUser('role') role: string,
    @Query('eventName') eventName?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
  ) {
    if (role !== 'admin') {
      throw new ForbiddenException('Admin access required');
    }
    return this.analyticsService.getDailyCounts({
      eventName: eventName || undefined,
      from: from ? new Date(from) : undefined,
      to: to ? new Date(to) : undefined,
    });
  }

  /**
   * GET /api/admin/analytics/event-count?eventName=X&userId=Y
   * Returns the total count of a specific event, optionally filtered
   * by userId. Used by the Flutter onboarding flow to check if a user
   * has sent their first message (first_message_in_chat event count).
   */
  @Get('analytics/event-count')
  async getEventCount(
    @CurrentUser('role') role: string,
    @Query('eventName') eventName: string,
    @Query('userId') userId?: string,
  ) {
    if (role !== 'admin') {
      throw new ForbiddenException('Admin access required');
    }
    const count = await this.analyticsService.getEventCount(eventName, userId);
    return { eventName, userId: userId ?? null, count };
  }
}
