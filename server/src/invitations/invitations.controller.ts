import { Controller, Post, Param, UseGuards } from '@nestjs/common';
import { SupabaseAuthGuard } from '../auth/supabase-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { InvitationsService } from './invitations.service';

@Controller('invitations')
export class InvitationsController {
  constructor(private readonly invitationsService: InvitationsService) {}

  @Post(':id/accept')
  @UseGuards(SupabaseAuthGuard)
  async acceptInvitation(@CurrentUser() user: any, @Param('id') id: string) {
    return this.invitationsService.acceptInvitation(user.id, id);
  }

  @Post(':id/decline')
  @UseGuards(SupabaseAuthGuard)
  async declineInvitation(@CurrentUser() user: any, @Param('id') id: string) {
    return this.invitationsService.declineInvitation(user.id, id);
  }
}
