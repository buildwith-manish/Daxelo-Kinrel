import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  Req,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { Request } from 'express';
import { SupportService } from './support.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CreateTicketDto } from './dto/create-ticket.dto';
import { CreateMessageDto } from './dto/create-message.dto';
import { CreateCsatDto } from './dto/create-csat.dto';

@Controller('support/tickets')
export class SupportController {
  constructor(private supportService: SupportService) {}

  /**
   * GET /api/support/tickets/my
   * User's own tickets — must be defined BEFORE :ticketId route
   */
  @Get('my')
  @UseGuards(JwtAuthGuard)
  async getMyTickets(
    @Req() req: Request,
    @Query('status') status?: string,
    @Query('page') pageStr?: string,
    @Query('limit') limitStr?: string,
  ) {
    const userId = (req as any).user?.id ?? req.headers['x-user-id'] as string;
    const page = pageStr ? parseInt(pageStr, 10) : 1;
    const limit = limitStr ? parseInt(limitStr, 10) : 20;
    return this.supportService.getMyTickets(userId, { status, page, limit });
  }

  /**
   * GET /api/support/tickets?status=&page=&limit=
   * List tickets (paginated)
   */
  @Get()
  @UseGuards(JwtAuthGuard)
  async listTickets(
    @Query('status') status?: string,
    @Query('page') pageStr?: string,
    @Query('limit') limitStr?: string,
  ) {
    const page = pageStr ? parseInt(pageStr, 10) : 1;
    const limit = limitStr ? parseInt(limitStr, 10) : 20;
    return this.supportService.listTickets({ status, page, limit });
  }

  /**
   * POST /api/support/tickets
   * Create ticket
   */
  @Post()
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.CREATED)
  async createTicket(
    @Req() req: Request,
    @Body() dto: CreateTicketDto,
  ) {
    const userId = (req as any).user?.id ?? req.headers['x-user-id'] as string;
    return this.supportService.createTicket(userId, dto);
  }

  /**
   * POST /api/support/tickets/:ticketId/messages
   * Add message to ticket
   */
  @Post(':ticketId/messages')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.CREATED)
  async createMessage(
    @Req() req: Request,
    @Param('ticketId') ticketId: string,
    @Body() dto: CreateMessageDto,
  ) {
    const userId = (req as any).user?.id ?? req.headers['x-user-id'] as string;
    return this.supportService.createMessage(userId, ticketId, dto);
  }

  /**
   * GET /api/support/tickets/:ticketId/messages
   * List messages for ticket
   */
  @Get(':ticketId/messages')
  @UseGuards(JwtAuthGuard)
  async listMessages(
    @Req() req: Request,
    @Param('ticketId') ticketId: string,
  ) {
    const userId = (req as any).user?.id ?? req.headers['x-user-id'] as string;
    return this.supportService.listMessages(userId, ticketId);
  }

  /**
   * POST /api/support/tickets/:ticketId/csat
   * Submit CSAT rating
   */
  @Post(':ticketId/csat')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.CREATED)
  async createCsat(
    @Req() req: Request,
    @Param('ticketId') ticketId: string,
    @Body() dto: CreateCsatDto,
  ) {
    const userId = (req as any).user?.id ?? req.headers['x-user-id'] as string;
    return this.supportService.createCsat(userId, ticketId, dto);
  }
}
