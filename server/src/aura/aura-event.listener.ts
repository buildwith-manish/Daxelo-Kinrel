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

  // Bug 7 fix: in-flight lock per family. Once a `computeAndSave` is
  // running for a family, any new event for that family reschedules
  // itself for 500ms later (instead of starting a concurrent
  // `computeAndSave`). Without this lock, two concurrent
  // `computeAndSave` calls would both `prisma.familyAura.upsert(...)`
  // + `prisma.familyAuraHistory.create(...)` → last-writer-wins on
  // the upsert, duplicate history rows, and possibly inconsistent
  // `MemberAuraRole` rows.
  private readonly inFlight = new Set<string>();

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

  // How long to wait before retrying when a `computeAndSave` is already
  // in-flight for the same family. Picked to be small enough that the
  // user doesn't notice, but large enough that the in-flight compute
  // has a fair chance to finish.
  private readonly INFLIGHT_RETRY_MS = 500;

  constructor(private readonly orchestration: AuraOrchestrationService) {}

  // ── Event Handlers ────────────────────────────────────────────
  //
  // All events route to the same handler — the debounce logic is
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

  // Bug 8 fix: removed the `family.member.updated` handler. A member
  // update (name, DOB, avatar, languageTag) changes zero graph edges,
  // and `computeLanguageDistribution` derives the distribution from
  // `edge.languageTag` + `relationshipType`, NOT from member fields.
  // So the language distribution and all graph metrics are byte-identical
  // for a member-only update — the recompute was burning CPU + Prisma
  // writes for nothing, and (with Bug 7 unfixed) could stack on top of
  // an unrelated concurrent recompute.
  // If a future feature adds member-level language preferences that
  // should affect the AURA, re-add this handler at that time.

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
    const timeout = setTimeout(() => {
      this.pendingRecomputes.delete(familyId);

      // Bug 7 fix: if a compute is already in-flight for this family,
      // reschedule for INFLIGHT_RETRY_MS later instead of starting a
      // concurrent one. This prevents overlapping `computeAndSave`
      // calls that race on the same `familyAura` row.
      if (this.inFlight.has(familyId)) {
        this.logger.debug(
          `AURA recompute for family ${familyId} deferred — another compute is in-flight`,
        );
        this.scheduleRecompute(familyId, trigger);
        return;
      }

      // Mark as in-flight BEFORE the async call so concurrent timers
      // see the lock. The `void` return of this setTimeout callback
      // means we can't `await` here — fire-and-forget with a .finally()
      // to release the lock.
      this.inFlight.add(familyId);
      const latest = this.latestTrigger.get(familyId);
      this.latestTrigger.delete(familyId);

      this.orchestration
        .computeAndSave(familyId, {
          triggerMemberId: latest?.memberId ?? null,
          triggerEventType: latest?.eventType ?? 'manual_recompute',
        })
        .catch((error: unknown) => {
          this.logger.error(
            `AURA recompute failed for family ${familyId}: ${
              error instanceof Error ? error.message : error
            }`,
            error instanceof Error ? error.stack : undefined,
          );
        })
        .finally(() => {
          this.inFlight.delete(familyId);
        });
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
    this.inFlight.clear();
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

  /** Returns true if a recompute is currently in-flight for the given family. */
  isInFlight(familyId: string): boolean {
    return this.inFlight.has(familyId);
  }
}
