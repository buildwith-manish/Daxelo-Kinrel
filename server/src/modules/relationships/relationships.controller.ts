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
import { ApiTags } from '@nestjs/swagger';
import { RelationshipsService } from './relationships.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { PaginationDto } from '../../common/dto/pagination.dto';
import { CreateRelationshipDto } from './dto/create-relationship.dto';

@ApiTags('Relationships')
@Controller('families/:familyId/relationships')
@UseGuards(JwtAuthGuard)
export class RelationshipsController {
  constructor(private relationshipsService: RelationshipsService) {}

  @Get()
  async findAll(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Query('personId') personId?: string,
    @Query() pagination?: PaginationDto,
  ) {
    return this.relationshipsService.findAll(userId, familyId, { personId }, pagination);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async create(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() dto: CreateRelationshipDto,
  ) {
    return this.relationshipsService.create(userId, familyId, dto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  async remove(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('id') id: string,
  ) {
    return this.relationshipsService.remove(userId, familyId, id);
  }
}
