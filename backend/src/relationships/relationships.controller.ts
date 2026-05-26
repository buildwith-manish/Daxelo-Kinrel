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
  Res,
} from '@nestjs/common';
import { Response } from 'express';
import { RelationshipsService } from './relationships.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { CreateRelationshipDto } from './dto/create-relationship.dto';

@Controller('families/:familyId/relationships')
@UseGuards(JwtAuthGuard)
export class RelationshipsController {
  constructor(private relationshipsService: RelationshipsService) {}

  /**
   * GET /api/families/:familyId/relationships
   * List relationships (filterable by personId, paginated)
   * Response: { data: [...relationships], pagination: {...} }
   */
  @Get()
  async listRelationships(
    @CurrentUser() user: { id: string },
    @Param('familyId') familyId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('personId') personId?: string,
  ) {
    return this.relationshipsService.listRelationships(familyId, user.id, {
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
      personId,
    });
  }

  /**
   * POST /api/families/:familyId/relationships
   * Create relationship (member+ role)
   * Response: { data: {...relationship} } with status 201
   */
  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createRelationship(
    @CurrentUser() user: { id: string },
    @Param('familyId') familyId: string,
    @Body() dto: CreateRelationshipDto,
  ) {
    return this.relationshipsService.createRelationship(familyId, user.id, dto);
  }

  /**
   * DELETE /api/families/:familyId/relationships?id=xxx
   * Delete relationship and inverse (editor+ role)
   * Response: status 204, no body
   */
  @Delete()
  @HttpCode(HttpStatus.NO_CONTENT)
  async deleteRelationship(
    @CurrentUser() user: { id: string },
    @Param('familyId') familyId: string,
    @Query('id') id: string,
    @Res() res: Response,
  ) {
    await this.relationshipsService.deleteRelationship(familyId, id, user.id);
    res.status(HttpStatus.NO_CONTENT).send();
  }
}
