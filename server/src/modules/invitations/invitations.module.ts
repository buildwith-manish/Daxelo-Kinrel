import { Module, forwardRef } from '@nestjs/common';
import { InvitationsController } from './invitations.controller';
import { InvitationsService } from './invitations.service';
import { FamiliesModule } from '../families/families.module';
import { GatewayModule } from '../gateway/gateway.module';
import { NotificationsModule } from '../notifications/notifications.module';

@Module({
  imports: [FamiliesModule, GatewayModule, forwardRef(() => NotificationsModule)],
  controllers: [InvitationsController],
  providers: [InvitationsService],
})
export class InvitationsModule {}
