// server/src/modules/chat/chat-exports.controller.ts
//
// DAXELO KINREL — Tier 5 Feature 5.4: Chat export — Controller

import { Body, Controller, Delete, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { ChatExportsService } from './chat-exports.service';

@Controller('chat/exports')
@UseGuards(JwtAuthGuard)
export class ChatExportsController {
  constructor(private readonly service: ChatExportsService) {}

  /// POST /chat/exports
  /// Body: { familyId, scope: 'text' | 'full' }
  /// Create a chat export job.
  @Post()
  async create(
    @CurrentUser('id') userId: string,
    @Body() body: { familyId: string; scope: 'text' | 'full' },
  ) {
    return this.service.createExportJob(userId, body);
  }

  /// GET /chat/exports/:id
  /// Get a single export job's status.
  @Get(':id')
  async get(@CurrentUser('id') userId: string, @Param('id') id: string) {
    return this.service.getJob(userId, id);
  }

  /// GET /chat/exports?limit=20
  /// List the caller's recent export jobs.
  @Get()
  async list(@CurrentUser('id') userId: string, @Query('limit') limit?: string) {
    return this.service.listMyJobs(userId, limit ? parseInt(limit, 10) : 20);
  }

  /// DELETE /chat/exports/:id
  /// Cancel a pending job.
  @Delete(':id')
  async cancel(@CurrentUser('id') userId: string, @Param('id') id: string) {
    return this.service.cancelJob(userId, id);
  }
}
