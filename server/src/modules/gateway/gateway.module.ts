import { Module, OnModuleInit } from '@nestjs/common';
import { KinrelGateway } from './kinrel.gateway';
import { PresenceService } from './presence.service';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  // PrismaModule is global, but importing it explicitly here makes the
  // dependency clear for the PresenceService.
  imports: [PrismaModule],
  providers: [KinrelGateway, PresenceService],
  exports: [KinrelGateway, PresenceService],
})
export class GatewayModule implements OnModuleInit {
  constructor(
    private readonly gateway: KinrelGateway,
    private readonly presence: PresenceService,
  ) {}

  onModuleInit() {
    // Inject the gateway's emitToFamily helper into the PresenceService
    // so it can broadcast 'presenceUpdate' events without a circular DI.
    // This is called once at app startup, after both services are
    // instantiated.
    this.presence.setEmitToFamilyFn((familyId, event, payload) => {
      this.gateway.emitToFamily(familyId, event, payload as any);
    });
  }
}
