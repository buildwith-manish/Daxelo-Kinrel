import { Controller, Post, Body, UseGuards } from '@nestjs/common';
import { SupabaseAuthGuard } from '../auth/supabase-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { SupportService } from './support.service';

@Controller('support')
export class SupportController {
  constructor(private readonly supportService: SupportService) {}

  @Post('tickets')
  @UseGuards(SupabaseAuthGuard)
  async createTicket(
    @CurrentUser() user: any,
    @Body() body: { subject: string; message: string },
  ) {
    const ticket = await this.supportService.createTicket(user.id, body);
    return { ticket };
  }
}
