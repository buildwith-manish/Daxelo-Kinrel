import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  UseGuards,
} from '@nestjs/common';
import { SupabaseAuthGuard } from '../auth/supabase-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { FamiliesService } from './families.service';
import { CreateFamilyDto } from '../dto/create-family.dto';
import { UpdateFamilyDto } from '../dto/update-family.dto';

@Controller('families')
export class FamiliesController {
  constructor(private readonly familiesService: FamiliesService) {}

  @Get()
  @UseGuards(SupabaseAuthGuard)
  async listFamilies(@CurrentUser() user: any) {
    const families = await this.familiesService.listFamilies(user.id);
    return { families };
  }

  @Post()
  @UseGuards(SupabaseAuthGuard)
  async createFamily(@CurrentUser() user: any, @Body() body: CreateFamilyDto) {
    const family = await this.familiesService.createFamily(user.id, body);
    return { family };
  }

  @Get(':id')
  @UseGuards(SupabaseAuthGuard)
  async getFamily(@CurrentUser() user: any, @Param('id') id: string) {
    const family = await this.familiesService.getFamily(user.id, id);
    return { family };
  }

  @Patch(':id')
  @UseGuards(SupabaseAuthGuard)
  async updateFamily(
    @CurrentUser() user: any,
    @Param('id') id: string,
    @Body() body: UpdateFamilyDto,
  ) {
    const family = await this.familiesService.updateFamily(user.id, id, body);
    return { family };
  }

  @Delete(':id')
  @UseGuards(SupabaseAuthGuard)
  async deleteFamily(@CurrentUser() user: any, @Param('id') id: string) {
    return this.familiesService.deleteFamily(user.id, id);
  }

  @Post(':id/export')
  @UseGuards(SupabaseAuthGuard)
  async exportFamily(@CurrentUser() user: any, @Param('id') id: string) {
    return this.familiesService.exportFamily(user.id, id);
  }
}
