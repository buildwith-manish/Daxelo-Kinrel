// server/src/aura/aura-event.listener.ts
//
// AURA — Event Listener for Real-Time Recalculation
//
// Listens to domain events emitted by SupabaseRealtimeService when
// Person or Relationship rows change. Debounces 2s per family to batch
// rapid changes (e.g., bulk imports), then triggers a full AURA
// recomputation via AuraOrchestrationService.
//
// Events listened to:
//   family.member.added         → { familyId, memberId? }
//   family.member.removed       → { familyId, memberId? }
//   family.relationship.created → { familyId, memberId? }
//   family.relationship.deleted → { familyId, memberId? }
//   family.relationship.updated → { familyId, memberId? }
//
// Debounce strategy:
//   - One timer per familyId.
//   - Each new event for the same family resets the timer.
//   - After DEBOUNCE_MS of silence, computeAndSave() fires once.
//   - This means 100 rapid member adds → 1 AURA recompute, not 100.

import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { OnEvent } from '@nestjs/event-emitter';
import { AuraOrchestrationService } from './aura-orchestration.service';

// Event payload shape — matches what SupabaseRealtimeService emits.
export interface FamilyChangeEvent {
  familyId: string;
  memberId?: string;
  eventType?: string;
}

@Injectable()
export class AuraEventListener implements OnModuleDestroy {
  private readonly logger = new Logger(AuraEventListener.name);

  // Debounce timers per family: familyId → timeout handle
  private readonly pendingRecomputes = new Map<string, NodeJS.Timeout>();

  // Track the latest trigger info per family so the debounced recompute
  // can pass the most recent memberId/eventType to the history snapshot.
  private readonly latestTrigger = new Map<
    string,
    { memberId?: string; eventType: string }
  >();

  // Wait 2s after the last change event before computing. This batches
  // rapid changes (bulk imports, multi-step relationship edits) into a
  // single recompute.
  private readonly DEBOUNCE_MS = 2000;

  constructor(private readonly orchestration: AuraOrchestrationService) {}

  // ── Event Handlers ────────────────────────────────────────────
  //
  // All five events route to the same handler — the debounce logic is
  // identical, only the eventType label differs (for the history snapshot).

  @OnEvent('family.member.added')
  handleMemberAdded(payload: FamilyChangeEvent) {
    this.scheduleRecompute(payload.familyId, {
      memberId: payload.memberId,
      eventType: 'member_added',
    });
  }

  @OnEvent('family.member.removed')
  handleMemberRemoved(payload: FamilyChangeEvent) {
    this.scheduleRecompute(payload.familyId, {
      memberId: payload.memberId,
      eventType: 'member_removed',
    });
  }

  @OnEvent('family.member.updated')
  handleMemberUpdated(payload: FamilyChangeEvent) {
    // Member updates (e.g., name change) don't affect graph topology,
    // but we still recompute to refresh role glyph colors if the
    // language distribution changed. Cheap to do — debounced.
    this.scheduleRecompute(payload.familyId, {
      memberId: payload.memberId,
      eventType: 'member_updated',
    });
  }

  @OnEvent('family.relationship.created')
  handleRelationshipCreated(payload: FamilyChangeEvent) {
    this.scheduleRecompute(payload.familyId, {
      memberId: payload.memberId,
      eventType: 'relationship_created',
    });
  }

  @OnEvent('family.relationship.deleted')
  handleRelationshipDeleted(payload: FamilyChangeEvent) {
    this.scheduleRecompute(payload.familyId, {
      memberId: payload.memberId,
      eventType: 'relationship_deleted',
    });
  }

  @OnEvent('family.relationship.updated')
  handleRelationshipUpdated(payload: FamilyChangeEvent) {
    this.scheduleRecompute(payload.familyId, {
      memberId: payload.memberId,
      eventType: 'relationship_updated',
    });
  }

  // ── Debounce Logic ────────────────────────────────────────────

  private scheduleRecompute(
    familyId: string,
    trigger: { memberId?: string; eventType: string },
  ): void {
    this.logger.debug(
      `AURA recompute scheduled for family ${familyId} (trigger: ${trigger.eventType}, memberId: ${trigger.memberId ?? 'none'})`,
    );

    // Update the latest trigger info (overwrites previous — we only care
    // about the most recent event when the debounced recompute fires)
    this.latestTrigger.set(familyId, trigger);

    // Cancel any pending recompute for this family
    const existing = this.pendingRecomputes.get(familyId);
    if (existing) {
      clearTimeout(existing);
    }

    // Schedule a new recompute after the debounce window
    const timeout = setTimeout(async () => {
      this.pendingRecomputes.delete(familyId);
      const latest = this.latestTrigger.get(familyId);
      this.latestTrigger.delete(familyId);

      try {
        await this.orchestration.computeAndSave(familyId, {
          triggerMemberId: latest?.memberId ?? null,
          triggerEventType: latest?.eventType ?? 'manual_recompute',
        });
      } catch (error) {
        this.logger.error(
          `AURA recompute failed for family ${familyId}: ${
            error instanceof Error ? error.message : error
          }`,
          error instanceof Error ? error.stack : undefined,
        );
      }
    }, this.DEBOUNCE_MS);

    this.pendingRecomputes.set(familyId, timeout);
  }

  // ── Lifecycle ─────────────────────────────────────────────────

  onModuleDestroy() {
    // Clear all pending timers on shutdown to prevent dangling timeouts
    for (const timeout of this.pendingRecomputes.values()) {
      clearTimeout(timeout);
    }
    this.pendingRecomputes.clear();
    this.latestTrigger.clear();
    this.logger.log('AuraEventListener destroyed — cleared all pending recomputes');
  }

  // ── Test helpers (used by validation scripts) ────────────────

  /** Returns the number of families with pending (debounced) recomputes. */
  get pendingCount(): number {
    return this.pendingRecomputes.size;
  }

  /** Returns true if a recompute is pending for the given family. */
  isPending(familyId: string): boolean {
    return this.pendingRecomputes.has(familyId);
  }
}
