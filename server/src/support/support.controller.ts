import { Controller, Post, Body, UseGuards } from '@nestjs/common';
import { SupabaseAuthGuard } from '../auth/supabase-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { SupportService } from './support.service';
import { CreateTicketDto } from '../dto/create-ticket.dto';

@Controller('support')
export class SupportController {
  constructor(private readonly supportService: SupportService) {}

  @Post('tickets')
  @UseGuards(SupabaseAuthGuard)
  async createTicket(
    @CurrentUser() user: any,
    @Body() body: CreateTicketDto,
  ) {
    const ticket = await this.supportService.createTicket(user.id, body);
    return { ticket };
  }
}
