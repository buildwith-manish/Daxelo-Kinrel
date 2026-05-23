import {
  Controller,
  Get,
  Post,
  Delete,
  Body,
  Req,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import type { Request } from 'express';
import { DeveloperService } from './developer.service';
import { CreateKeyDto, RevokeKeyDto } from './dto/create-key.dto';

/**
 * DeveloperController — /api/v1/developer/*
 *
 * Routes:
 * - GET    /api/v1/developer/keys  — List API keys
 * - POST   /api/v1/developer/keys  — Create key
 * - DELETE /api/v1/developer/keys  — Revoke key
 */
@Controller('v1/developer')
export class DeveloperController {
  constructor(private readonly developerService: DeveloperService) {}

  @Get('keys')
  async listKeys(@Req() req: Request) {
    const userId = (req as any).apiKey?.userId;
    if (!userId) return { error: 'Unauthorized' };
    return this.developerService.listKeys(userId);
  }

  @Post('keys')
  @HttpCode(HttpStatus.CREATED)
  async createKey(@Req() req: Request, @Body() dto: CreateKeyDto) {
    const userId = (req as any).apiKey?.userId;
    if (!userId) return { error: 'Unauthorized' };
    return this.developerService.createKey(userId, dto);
  }

  @Delete('keys')
  async revokeKey(@Req() req: Request, @Body() dto: RevokeKeyDto) {
    const userId = (req as any).apiKey?.userId;
    if (!userId) return { error: 'Unauthorized' };
    return this.developerService.revokeKey(userId, dto);
  }
}
