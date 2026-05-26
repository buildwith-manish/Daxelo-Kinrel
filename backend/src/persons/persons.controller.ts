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
  Res,
} from '@nestjs/common';
import { Response } from 'express';
import { PersonsService } from './persons.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { CreatePersonDto } from './dto/create-person.dto';
import { UpdatePersonDto } from './dto/update-person.dto';

@Controller('families/:familyId/persons')
@UseGuards(JwtAuthGuard)
export class PersonsController {
  constructor(private personsService: PersonsService) {}

  /**
   * GET /api/families/:familyId/persons
   * List persons (paginated, filterable)
   * Response: { data: [...persons], pagination: { page, limit, total, hasMore, totalPages } }
   */
  @Get()
  async listPersons(
    @CurrentUser() user: { id: string },
    @Param('familyId') familyId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('deceased') deceased?: string,
    @Query('search') search?: string,
    @Query('sort') sort?: string,
    @Query('order') order?: string,
    @Query('includeRelationships') includeRelationships?: string,
  ) {
    return this.personsService.listPersons(familyId, user.id, {
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
      deceased,
      search,
      sort,
      order,
      includeRelationships,
    });
  }

  /**
   * POST /api/families/:familyId/persons
   * Create person (member+ role required, kinship validation)
   * Response: { data: {...person} } with status 201
   */
  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createPerson(
    @CurrentUser() user: { id: string },
    @Param('familyId') familyId: string,
    @Body() dto: CreatePersonDto,
  ) {
    return this.personsService.createPerson(familyId, user.id, dto);
  }

  /**
   * GET /api/families/:familyId/persons/:personId
   * Get single person with relationships
   * Response: { data: {...person} }
   */
  @Get(':personId')
  async getPerson(
    @CurrentUser() user: { id: string },
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
  ) {
    return this.personsService.getPerson(familyId, personId, user.id);
  }

  /**
   * PATCH /api/families/:familyId/persons/:personId
   * Update person (editor+ role required)
   * Response: { data: {...person} }
   */
  @Patch(':personId')
  async updatePerson(
    @CurrentUser() user: { id: string },
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
    @Body() dto: UpdatePersonDto,
  ) {
    return this.personsService.updatePerson(familyId, personId, user.id, dto);
  }

  /**
   * DELETE /api/families/:familyId/persons/:personId
   * Soft delete person (admin only)
   * Response: status 204, no body
   */
  @Delete(':personId')
  @HttpCode(HttpStatus.NO_CONTENT)
  async deletePerson(
    @CurrentUser() user: { id: string },
    @Param('familyId') familyId: string,
    @Param('personId') personId: string,
    @Res() res: Response,
  ) {
    await this.personsService.deletePerson(familyId, personId, user.id);
    res.status(HttpStatus.NO_CONTENT).send();
  }
}
