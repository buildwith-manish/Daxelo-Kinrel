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
  BadRequestException,
} from '@nestjs/common';
import { RelationshipsService } from './relationships.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { PaginationDto } from '../../common/dto/pagination.dto';
import { CreateRelationshipDto } from './dto/create-relationship.dto';

@Controller('families/:familyId')
@UseGuards(JwtAuthGuard)
export class RelationshipsController {
  constructor(private relationshipsService: RelationshipsService) {}

  @Get('relationships')
  async findAll(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Query('personId') personId?: string,
    @Query() pagination?: PaginationDto,
  ) {
    return this.relationshipsService.findAll(familyId, userId, { personId }, pagination);
  }

  @Post('relationships')
  @HttpCode(HttpStatus.CREATED)
  async create(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() dto: CreateRelationshipDto,
  ) {
    return this.relationshipsService.create(userId, familyId, dto);
  }

  @Delete('relationships/:id')
  @HttpCode(HttpStatus.OK)
  async remove(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('id') id: string,
  ) {
    return this.relationshipsService.remove(userId, familyId, id);
  }

  /**
   * GET /families/:familyId/relationship-path?from=:viewerId&to=:targetId
   *
   * v2.2 — Returns the cached relationship path between two persons in a family.
   * Uses the existing `RelationshipPathCache` table; falls through to
   * `GraphEngineService.findPath` when no cache hit.
   */
  @Get('relationship-path')
  async getRelationshipPath(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Query('from') fromPersonId?: string,
    @Query('to') toPersonId?: string,
  ) {
    if (!fromPersonId || !toPersonId) {
      throw new BadRequestException(
        'Both `from` and `to` query parameters are required',
      );
    }
    return this.relationshipsService.getRelationshipPath(
      userId,
      familyId,
      fromPersonId,
      toPersonId,
    );
  }
}
