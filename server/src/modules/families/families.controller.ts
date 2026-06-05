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
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { FamiliesService } from './families.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { PaginationDto } from '../../common/dto/pagination.dto';
import { CreateFamilyDto } from './dto/create-family.dto';
import { UpdateFamilyDto } from './dto/update-family.dto';

@ApiTags('families')
@Controller('families')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class FamiliesController {
  constructor(private familiesService: FamiliesService) {}

  @Get()
  @ApiOperation({ summary: 'Get all families for the current user' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns paginated list of families' })
  async findAll(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationDto,
  ) {
    return this.familiesService.findAll(userId, pagination);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a new family' })
  @ApiResponse({ status: HttpStatus.CREATED, description: 'Family created successfully' })
  @ApiResponse({ status: HttpStatus.BAD_REQUEST, description: 'Invalid input data' })
  async create(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateFamilyDto,
  ) {
    return this.familiesService.create(userId, dto);
  }

  @Get(':familyId')
  @ApiOperation({ summary: 'Get a family by ID' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns the family details' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Family not found' })
  async findOne(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.familiesService.findOne(userId, familyId);
  }

  @Patch(':familyId')
  @ApiOperation({ summary: 'Update a family' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Family updated successfully' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Family not found' })
  async update(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() dto: UpdateFamilyDto,
  ) {
    return this.familiesService.update(userId, familyId, dto);
  }

  @Delete(':familyId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Delete a family' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Family deleted successfully' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Family not found' })
  async remove(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.familiesService.remove(userId, familyId);
  }

  @Delete(':familyId/leave')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Leave a family as a non-admin member' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Left family successfully' })
  @ApiResponse({ status: HttpStatus.BAD_REQUEST, description: 'Cannot leave as the only admin' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Not a member of this family' })
  async leaveFamily(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.familiesService.leaveFamily(userId, familyId);
  }
}
