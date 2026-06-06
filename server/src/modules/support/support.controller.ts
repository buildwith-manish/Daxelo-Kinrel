import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { SupportService } from './support.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { CreateTicketDto } from './dto/create-ticket.dto';
import { AddMessageDto } from './dto/add-message.dto';

@Controller('support/tickets')
@UseGuards(JwtAuthGuard)
export class SupportController {
  constructor(private readonly supportService: SupportService) {}

  /**
   * GET /api/support/tickets/my
   * Get the authenticated user's own tickets.
   * Must be defined before the :ticketId param route.
   */
  @Get('my')
  async listMyTickets(
    @CurrentUser('id') userId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.supportService.listMyTickets(
      userId,
      page ? parseInt(page, 10) : 1,
      limit ? parseInt(limit, 10) : 20,
    );
  }

  /**
   * GET /api/support/tickets
   * List all tickets (admin/agent view, paginated).
   */
  @Get()
  @UseGuards(RolesGuard)
  @Roles('admin')
  async listTickets(
    @CurrentUser('id') userId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('status') status?: string,
    @Query('category') category?: string,
    @Query('queue') queue?: string,
  ) {
    return this.supportService.listTickets(
      page ? parseInt(page, 10) : 1,
      limit ? parseInt(limit, 10) : 20,
      { status, category, queue },
    );
  }

  /**
   * POST /api/support/tickets
   * Create a support ticket.
   */
  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createTicket(
    @CurrentUser('id') userId: string,
    @Body() body: CreateTicketDto,
  ) {
    return this.supportService.createTicket(userId, body);
  }

  /**
   * POST /api/support/tickets/:ticketId/messages
   * Add a message to a ticket.
   */
  @Post(':ticketId/messages')
  @HttpCode(HttpStatus.CREATED)
  async addMessage(
    @CurrentUser('id') userId: string,
    @Param('ticketId') ticketId: string,
    @Body() body: AddMessageDto,
  ) {
    return this.supportService.addMessage(ticketId, userId, body);
  }

  /**
   * POST /api/support/tickets/:ticketId/csat
   * Submit CSAT rating for a ticket.
   */
  @Post(':ticketId/csat')
  @HttpCode(HttpStatus.CREATED)
  async submitCSAT(
    @CurrentUser('id') userId: string,
    @Param('ticketId') ticketId: string,
    @Body()
    body: {
      rating: number;
      comment?: string;
    },
  ) {
    return this.supportService.submitCSAT(ticketId, userId, body);
  }
}
