import {
  Controller,
  Get,
  Post,
  Param,
  Body,
  Query,
  Headers,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { SupportService } from './support.service';
import { CreateTicketDto } from './dto/create-ticket.dto';
import { CreateMessageDto } from './dto/create-message.dto';
import { CsatDto } from './dto/csat.dto';

/**
 * SupportController
 *
 * Routes:
 * - POST   /api/support/tickets              — Create ticket
 * - GET    /api/support/tickets              — List all tickets
 * - GET    /api/support/tickets/my           — My tickets
 * - POST   /api/support/tickets/:ticketId/messages  — Add message
 * - GET    /api/support/tickets/:ticketId/messages  — Get messages
 * - POST   /api/support/tickets/:ticketId/csat      — Submit CSAT
 */
@Controller('support/tickets')
export class SupportController {
  constructor(private readonly supportService: SupportService) {}

  // ── POST /api/support/tickets ─────────────────────────────────────
  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createTicket(
    @Headers('X-User-Id') userId: string,
    @Body() dto: CreateTicketDto,
  ) {
    if (!userId) {
      return { error: 'Unauthorized — X-User-Id header required' };
    }
    return this.supportService.createTicket(userId, dto);
  }

  // ── GET /api/support/tickets ──────────────────────────────────────
  @Get()
  async listTickets(
    @Query('status') status?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.supportService.listTickets({
      status: status || undefined,
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  // ── GET /api/support/tickets/my ───────────────────────────────────
  // IMPORTANT: This must come before the :ticketId param route
  @Get('my')
  async myTickets(
    @Headers('X-User-Id') userId: string,
    @Query('status') status?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    if (!userId) {
      return { error: 'Unauthorized — X-User-Id header required' };
    }
    return this.supportService.myTickets(userId, {
      status: status || undefined,
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  // ── POST /api/support/tickets/:ticketId/messages ──────────────────
  @Post(':ticketId/messages')
  @HttpCode(HttpStatus.CREATED)
  async addMessage(
    @Headers('X-User-Id') userId: string,
    @Param('ticketId') ticketId: string,
    @Body() dto: CreateMessageDto,
  ) {
    if (!userId) {
      return { error: 'Unauthorized' };
    }
    return this.supportService.addMessage(userId, ticketId, dto);
  }

  // ── GET /api/support/tickets/:ticketId/messages ───────────────────
  @Get(':ticketId/messages')
  async getMessages(
    @Headers('X-User-Id') userId: string,
    @Param('ticketId') ticketId: string,
  ) {
    if (!userId) {
      return { error: 'Unauthorized' };
    }
    return this.supportService.getMessages(userId, ticketId);
  }

  // ── POST /api/support/tickets/:ticketId/csat ─────────────────────
  @Post(':ticketId/csat')
  @HttpCode(HttpStatus.CREATED)
  async submitCsat(
    @Headers('X-User-Id') userId: string,
    @Param('ticketId') ticketId: string,
    @Body() dto: CsatDto,
  ) {
    if (!userId) {
      return { error: 'Unauthorized' };
    }
    return this.supportService.submitCsat(userId, ticketId, dto);
  }
}
