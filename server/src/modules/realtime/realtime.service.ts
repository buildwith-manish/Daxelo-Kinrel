import { Injectable, Logger } from '@nestjs/common';

@Injectable()
export class RealtimeService {
  private readonly logger = new Logger(RealtimeService.name);

  prepareEvent(familyId: string, eventType: string, payload: any) {
    this.logger.debug(`Preparing event: ${eventType} for family: ${familyId}`);
    return { familyId, eventType, payload, timestamp: new Date().toISOString() };
  }
}
