// server/src/pulse/collectors/memory-orbit.collector.ts
//
// MemoryOrbitCollector — STUB for now (Phase 1).
//
// When Pitru ships (Pt-1 through Pt-5), this collector will resurface ancestral
// voice memories on anniversaries, festivals, and "the day they were recorded".
//
// For Phase 1, this collector returns []. The stub is important because the
// orchestrator already calls it — when Pitru ships, this collector lights up
// and the brief's "👵 New from the elders" section starts appearing.
//
// Future behavior (planned):
//   1. Query AncestralMemory rows where:
//        - familyId = ctx.familyId
//        - For each memory, compute "is this an anniversary of recording?"
//          (i.e., EXTRACT(MONTH/DAY FROM createdAt) = today's month/day AND year < current)
//        - OR "is this tagged to a festival happening today?" (via Festival Intelligence)
//        - OR "is this tagged to a Person whose birthday is today?"
//   2. Cap at 1 item.
//   3. Title: "{Elder name} shared a memory — {topic}"
//      Body: "{duration}-min {audio|video} about {event}. Recorded {yearsAgo} years ago."
//      ActionType: 'listen_memory'
//   4. Special case: if the Person is deceased, frame as memorial:
//      "{Elder name} left this memory for you. {yearsAgo} years ago today."

import { Injectable, Logger } from '@nestjs/common';
import { BriefCollector, BriefCollectorContext, BriefItemData } from '../brief-types';

@Injectable()
export class MemoryOrbitCollector implements BriefCollector {
  readonly name = 'memory_orbit';
  private readonly logger = new Logger(MemoryOrbitCollector.name);

  // PrismaService intentionally NOT injected — Pitru tables don't exist yet.
  // When Pt-1 ships, inject PrismaService and implement the real logic.

  async collect(_ctx: BriefCollectorContext): Promise<BriefItemData[]> {
    // Phase 1 stub: Pitru (ancestral memory) tables don't exist yet.
    // Return empty array so the orchestrator's "👵 New from the elders"
    // section simply doesn't appear in the brief until Pitru ships.
    this.logger.debug?.('MemoryOrbitCollector: stub — Pitru not yet implemented');
    return [];
  }
}
