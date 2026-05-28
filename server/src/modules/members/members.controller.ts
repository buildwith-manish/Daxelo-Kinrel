import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { MembersService } from './members.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { CreateMemberDto } from './dto/create-member.dto';
import { UpdateMemberDto } from './dto/update-member.dto';

@Controller('families/:familyId/persons')
@UseGuards(JwtAuthGuard)
export class MembersController {
  constructor(private membersService: MembersService) {}

  @Get()
  async findAll(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
    @Query('search') search?: string,
    @Query('sort') sort?: string,
    @Query('order') order?: string,
    @Query('includeRelationships') includeRelationships?: string,
  ) {
    return this.membersService.findAll(familyId, userId, {
      cursor: cursor || undefined,
      limit: limit ? parseInt(limit, 10) : 50,
      search,
      sort,
      order,
      includeRelationships,
    });
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async create(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() dto: CreateMemberDto,
  ) {
    return this.membersService.create(userId, familyId, dto);
  }

  @Get(':personId')
  async findOne(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
  ) {
    return this.membersService.findOne(userId, familyId, personId);
  }

  @Patch(':personId')
  async update(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
    @Body() dto: UpdateMemberDto,
  ) {
    return this.membersService.update(userId, familyId, personId, dto);
  }

  @Delete(':personId')
  @HttpCode(HttpStatus.OK)
  async remove(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
  ) {
    return this.membersService.remove(userId, familyId, personId);
  }
}
