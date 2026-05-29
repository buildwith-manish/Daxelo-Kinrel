import { Module } from '@nestjs/common';
import { InvitationsController } from './invitations.controller';
import { InvitationsService } from './invitations.service';
import { InvitationsV2Controller } from './invitations-v2.controller';
import { InvitationsV2Service } from './invitations-v2.service';
import { FamiliesModule } from '../families/families.module';
import { GatewayModule } from '../gateway/gateway.module';

@Module({
  imports: [FamiliesModule, GatewayModule],
  controllers: [InvitationsController, InvitationsV2Controller],
  providers: [InvitationsService, InvitationsV2Service],
  exports: [InvitationsService, InvitationsV2Service],
})
export class InvitationsModule {}
