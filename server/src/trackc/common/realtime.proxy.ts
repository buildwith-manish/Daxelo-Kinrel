// =============================================================================
// Track C v2.0 — Common: Realtime proxy
// =============================================================================
// Thin wrapper around the existing RealtimeService / KinrelGateway that other
// Track C modules use to broadcast family-scoped events.
//
// If the realtime infrastructure is unavailable, all calls are no-ops.
// =============================================================================

import { Injectable, Logger, Optional, ForwardRef, Inject } from '@nestjs/common';
import { RealtimeService as AppRealtimeService } from '../../modules/realtime/realtime.service';

@Injectable()
export class RealtimeService {
  private readonly logger = new Logger(RealtimeService.name);

  constructor(
    @Optional() private readonly appRealtime?: AppRealtimeService,
  ) {}

  /**
   * Broadcast a payload to all subscribers on a family's channel.
   * Best-effort: logs but does not throw on failure.
   */
  async broadcastFamily(familyId: string, event: string, payload: any): Promise<void> {
    if (!this.appRealtime) {
      this.logger.verbose(`Realtime not wired — skipping broadcast family=${familyId} event=${event}`);
      return;
    }
    try {
      // The existing RealtimeService exposes a `broadcastToFamily` method or similar.
      // We try a few common signatures to remain compatible.
      const anyRt = this.appRealtime as any;
      if (typeof anyRt.broadcastToFamily === 'function') {
        await anyRt.broadcastToFamily(familyId, event, payload);
        return;
      }
      if (typeof anyRt.emit === 'function') {
        await anyRt.emit(`family:${familyId}`, event, payload);
        return;
      }
      this.logger.warn(`No compatible broadcast method on RealtimeService`);
    } catch (err) {
      this.logger.warn(`broadcastFamily failed: ${(err as Error).message}`);
    }
  }
}
