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
import { PersonsService } from './persons.service';

@Controller('families/:familyId/persons')
export class PersonsController {
  constructor(private readonly personsService: PersonsService) {}

  @Get()
  @UseGuards(SupabaseAuthGuard)
  async listPersons(
    @CurrentUser() user: any,
    @Param('familyId') familyId: string,
  ) {
    const persons = await this.personsService.listPersons(user.id, familyId);
    return { persons };
  }

  @Post()
  @UseGuards(SupabaseAuthGuard)
  async addPerson(
    @CurrentUser() user: any,
    @Param('familyId') familyId: string,
    @Body() body: any,
  ) {
    const person = await this.personsService.addPerson(user.id, familyId, body);
    return { person };
  }
}

@Controller('persons')
export class PersonController {
  constructor(private readonly personsService: PersonsService) {}

  @Patch(':id')
  @UseGuards(SupabaseAuthGuard)
  async updatePerson(
    @CurrentUser() user: any,
    @Param('id') id: string,
    @Body() body: any,
  ) {
    const person = await this.personsService.updatePerson(user.id, id, body);
    return { person };
  }

  @Delete(':id')
  @UseGuards(SupabaseAuthGuard)
  async deletePerson(@CurrentUser() user: any, @Param('id') id: string) {
    return this.personsService.deletePerson(user.id, id);
  }
}
