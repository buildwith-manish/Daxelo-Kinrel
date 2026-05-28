import {
  Controller,
  Get,
  Post,
  Delete,
  Body,
  Param,
  UseGuards,
} from '@nestjs/common';
import { SupabaseAuthGuard } from '../auth/supabase-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { RelationshipsService } from './relationships.service';
import { CreateRelationshipDto } from '../dto/create-relationship.dto';

@Controller('families/:familyId/relationships')
export class RelationshipsController {
  constructor(private readonly relationshipsService: RelationshipsService) {}

  @Get()
  @UseGuards(SupabaseAuthGuard)
  async listRelationships(
    @CurrentUser() user: any,
    @Param('familyId') familyId: string,
  ) {
    const relationships = await this.relationshipsService.listRelationships(user.id, familyId);
    return { relationships };
  }

  @Post()
  @UseGuards(SupabaseAuthGuard)
  async createRelationship(
    @CurrentUser() user: any,
    @Param('familyId') familyId: string,
    @Body() body: CreateRelationshipDto,
  ) {
    const relationship = await this.relationshipsService.createRelationship(user.id, familyId, body);
    return { relationship };
  }
}

@Controller('relationships')
export class RelationshipController {
  constructor(private readonly relationshipsService: RelationshipsService) {}

  @Delete(':id')
  @UseGuards(SupabaseAuthGuard)
  async deleteRelationship(@CurrentUser() user: any, @Param('id') id: string) {
    return this.relationshipsService.deleteRelationship(user.id, id);
  }
}
