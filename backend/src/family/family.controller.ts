import { Controller, Get, Post, Body, UseGuards, Request } from '@nestjs/common';
import { FamilyService } from './family.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@Controller('families')
@UseGuards(JwtAuthGuard)
export class FamilyController {
  constructor(private familyService: FamilyService) {}

  /**
   * GET /api/families
   * Matches Next.js: { families: [...] }
   */
  @Get()
  async listFamilies(@Request() req) {
    return this.familyService.listFamilies(req.user.id);
  }

  /**
   * POST /api/families
   * Matches Next.js: { family: {...} } — 201
   */
  @Post()
  async createFamily(@Request() req, @Body() body: any) {
    return this.familyService.createFamily(req.user.id, body);
  }
}
