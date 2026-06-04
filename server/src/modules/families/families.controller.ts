import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { FamiliesService } from './families.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { CreateFamilyDto } from './dto/create-family.dto';
import { UpdateFamilyDto } from './dto/update-family.dto';

@Controller('families')
@UseGuards(JwtAuthGuard)
export class FamiliesController {
  constructor(private familiesService: FamiliesService) {}

  @Get()
  async findAll(@CurrentUser('id') userId: string) {
    return this.familiesService.findAll(userId);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async create(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateFamilyDto,
  ) {
    return this.familiesService.create(userId, dto);
  }

  @Get(':familyId')
  async findOne(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.familiesService.findOne(userId, familyId);
  }

  @Patch(':familyId')
  async update(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() dto: UpdateFamilyDto,
  ) {
    return this.familiesService.update(userId, familyId, dto);
  }

  @Delete(':familyId')
  @HttpCode(HttpStatus.OK)
  async remove(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.familiesService.remove(userId, familyId);
  }
}
