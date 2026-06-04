import {
  Controller,
  Get,
  Post,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { DeveloperService } from './developer.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('v1/developer/keys')
@UseGuards(JwtAuthGuard)
export class DeveloperKeysController {
  constructor(private readonly developerService: DeveloperService) {}

  /**
   * GET /api/v1/developer/keys
   * List user's API keys.
   */
  @Get()
  async listApiKeys(@CurrentUser('id') userId: string) {
    return this.developerService.listApiKeys(userId);
  }

  /**
   * POST /api/v1/developer/keys
   * Create a new API key.
   */
  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createApiKey(
    @CurrentUser('id') userId: string,
    @Body()
    body: {
      name: string;
      scopes?: string[];
      tier?: string;
    },
  ) {
    return this.developerService.createApiKey(userId, body);
  }

  /**
   * DELETE /api/v1/developer/keys?id=xxx
   * Revoke an API key.
   */
  @Delete()
  @HttpCode(HttpStatus.OK)
  async revokeApiKey(
    @CurrentUser('id') userId: string,
    @Query('id') id: string,
  ) {
    return this.developerService.revokeApiKey(id, userId);
  }
}
