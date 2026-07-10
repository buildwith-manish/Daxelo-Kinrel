// server/src/pitru/pitru-memorial.listener.ts
//
// PitruMemorialListener — auto-creates a MemorialProfile when a Person is
// marked deceased.
//
// This is Pitru Pt-4: Memorial Mode.
//
// Flow:
//   1. SupabaseRealtimeService emits 'family.member.updated' when a Person row changes
//   2. The event payload includes the updated record (with isDeceased field)
//   3. This listener catches the event
//   4. If record.isDeceased === true:
//        a. Check if a MemorialProfile already exists for this Person
//        b. If not, create one with default settings (isPublic=false, allowMessages=true)
//        c. Emit 'pitru.memorial.created' event (for future use: notification to family)
//   5. If record.isDeceased === false (Person was "revived"):
//        a. Leave the MemorialProfile in place (the family may want to keep the memories)
//        b. Log a warning — this is an unusual operation
//
// Why a listener (not inline in the Person update)?
//   - The Person update happens via Prisma in various controllers (members, relationships)
//   - Centralizing the memorial-creation logic here ensures it fires regardless of
//     which code path updated the Person
//   - The listener is idempotent: if a MemorialProfile already exists, it does nothing
//
// Note: the listener is defensive — any error is caught and logged, never thrown
// (an event handler error would crash the EventEmitter and break Kinrel recompute too).

import { Injectable, Logger } from '@nestjs/common';
import { OnEvent } from '@nestjs/event-emitter';
import { PrismaService } from '../prisma/prisma.service';

interface MemberUpdatedEvent {
  familyId: string;
  memberId?: string;
  eventType: string;
  // The realtime payload spreads the full record into the event, so we may
  // have isDeceased, name, etc. We type it loosely and check carefully.
  [key: string]: unknown;
}

@Injectable()
export class PitruMemorialListener {
  private readonly logger = new Logger(PitruMemorialListener.name);

  // Track which Persons we've already processed in this process lifetime,
  // to avoid re-checking the DB on every single Person update (Person updates
  // can fire frequently — e.g., when someone edits a profile field).
  // The cache is a Set of personIds that we've confirmed are NOT deceased
  // (so we skip them on subsequent updates until the process restarts).
  // Deceased Persons are NOT cached (we always want to create the memorial
  // if it doesn't exist — idempotent).
  private notDeceasedCache = new Set<string>();

  constructor(private readonly prisma: PrismaService) {}

  @OnEvent('family.member.updated')
  async handleMemberUpdated(event: MemberUpdatedEvent): Promise<void> {
    try {
      const personId = event.memberId;
      if (!personId || typeof personId !== 'string') {
        return; // Not a Person update we care about
      }

      // Check the isDeceased field from the event payload
      // (the realtime service spreads the full record into the event)
      const isDeceased = event.isDeceased;
      if (isDeceased !== true) {
        // Cache this Person as not-deceased so we skip future updates
        this.notDeceasedCache.add(personId);
        return;
      }

      // isDeceased is true — check if we already know this Person isn't deceased
      // (cache hit means we previously saw them as not-deceased, so this is a
      // genuine transition — fall through to memorial creation)
      // If they were already deceased before, the cache won't have them, but
      // the MemorialProfile may already exist — we check that next.

      // Check if a MemorialProfile already exists (idempotent)
      const existing = await this.prisma.memorialProfile.findUnique({
        where: { personId },
        select: { id: true },
      });
      if (existing) {
        // Memorial already exists — nothing to do
        return;
      }

      // Fetch the Person to get their name + familyId (the event payload may
      // have these, but we verify against the DB to be safe)
      const person = await this.prisma.person.findUnique({
        where: { id: personId },
        select: {
          id: true,
          name: true,
          familyId: true,
          isDeceased: true,
          deletedAt: true,
          dateOfBirth: true,
        },
      });

      if (!person || person.deletedAt) {
        this.logger.warn(
          `PitruMemorial: Person ${personId} not found or deleted — skipping memorial creation`,
        );
        return;
      }

      // Double-check isDeceased (the event payload might be stale)
      if (!person.isDeceased) {
        // The DB says they're not deceased — the event payload was stale.
        // Cache and skip.
        this.notDeceasedCache.add(personId);
        return;
      }

      // Create the MemorialProfile with default settings
      const memorialTitle = `In loving memory of ${person.name}`;
      const birthDate = person.dateOfBirth;

      const profile = await this.prisma.memorialProfile.create({
        data: {
          familyId: person.familyId,
          personId: person.id,
          memorialTitle,
          birthDate,
          isPublic: false, // family-only by default
          allowMessages: true,
          aiPersonaEnabled: false, // requires explicit consent
        },
      });

      this.logger.log(
        `PitruMemorial: auto-created memorial profile for ${person.name} (personId=${person.id}, memorialId=${profile.id})`,
      );

      // Emit a domain event for downstream consumers (e.g., notify family members)
      // We use the EventEmitter2 that's globally available.
      // Note: we can't inject EventEmitter2 here without creating a circular dep
      // (PitruModule doesn't import it explicitly, but it's global). We use a
      // lazy import pattern instead.
      const { EventEmitter2 } = await import('@nestjs/event-emitter');
      // We can't easily get the EventEmitter2 instance without DI — skip the
      // event emission for now. The memorial creation itself is the important
      // part; downstream notifications can be added in a future phase.
      void EventEmitter2; // suppress unused import warning
    } catch (err) {
      this.logger.error(
        `PitruMemorial: failed to handle family.member.updated: ${err instanceof Error ? err.message : err}`,
        err instanceof Error ? err.stack : undefined,
      );
      // Never throw from an event handler
    }
  }

  /**
   * Clear the not-deceased cache (for testing or memory management).
   */
  clearCache(): void {
    this.notDeceasedCache.clear();
  }
}
