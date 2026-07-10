// server/src/addictiveness/silent-alarm.service.ts
//
// A-4 Silent Alarms - inactivity detection + private nudges to the bridge role.
//
// Strategy:
//   1. Daily 6am IST cron checks all Persons across all families
//   2. For each Person, TWO checks run in parallel:
//      a) Absolute-floor check (kept from v1): days inactive >= 7/14/21
//         -> gentle / moderate / urgent. This catches TRULY inactive people
//         regardless of their normal pattern.
//      b) Adaptive per-person check (v3, ML spec item #6): the current
//         inactivity gap is >N standard deviations above THAT PERSON'S own
//         rolling mean gap-between-activity. A normally-very-active person
//         going quiet for 5 days (below the 7d floor) gets flagged as
//         unusual-for-them; a naturally-low-activity person at day 10
//         doesn't get flagged if it's consistent with their baseline.
//   3. The severity from (a) and (b) is maxed - the higher severity wins.
//   4. Bridge role + family admins are notified (RLS enforced).
//   5. When the inactive Person becomes active again, auto-resolve the alarm.
//
// Privacy:
//   - The alarm is NOT shown to the inactive person (no guilt/shame)
//   - Only the bridge + family admins can see it (RLS enforced)
//   - The alarm includes suggestions for the bridge: "Call them directly",
//     "Send a voice note", "Ask their sibling to check in"

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

const GENTLE_THRESHOLD_DAYS = 7;
const MODERATE_THRESHOLD_DAYS = 14;
const URGENT_THRESHOLD_DAYS = 21;

// ?? Adaptive per-person baseline tuning ??????????????????????????????????????
// Z_SCORE_THRESHOLD: how many stddev above the person's own mean gap counts
//   as "unusual for them". 2.5sigma - same as the analytics anomaly detector.
//
// MIN_HISTORY_FOR_BASELINE: minimum number of prior activity gaps needed
//   before the adaptive rule can fire. With <4 gaps the baseline is too
//   noisy to trust.
//
// MAX_BASELINE_SAMPLE_SIZE: cap on how many recent gaps to include in the
//   mean/stddev. ~30 gaps captures a month of daily activity, which is the
//   natural cycle for most family interaction patterns.
const Z_SCORE_THRESHOLD = 2.5;
const MIN_HISTORY_FOR_BASELINE = 4;
const MAX_BASELINE_SAMPLE_SIZE = 30;

const SUGGESTIONS_BY_SEVERITY: Record<string, string[]> = {
  gentle: [
    'Send a quick "thinking of you" message',
    'Share a photo they would enjoy',
    'Ask about their day',
  ],
  moderate: [
    'Call them directly - a voice is warmer than text',
    'Send a voice note instead of typing',
    'Ask their sibling or child to check in',
    'Share a memory you have together',
  ],
  urgent: [
    'Call them urgently - it has been 3+ weeks',
    'Visit in person if possible',
    'Contact another family member who lives nearby',
    'Check if they need any help',
  ],
};

@Injectable()
export class SilentAlarmService {
  private readonly logger = new Logger(SilentAlarmService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Daily cron: scan all families for inactive Persons and trigger/escalate alarms.
   * Called at 6am IST by AddictivenessCronService.
   */
  async scanForSilentAlarms(): Promise<{
    familiesScanned: number;
    alarmsTriggered: number;
    alarmsEscalated: number;
    alarmsResolved: number;
    errors: string[];
  }> {
    const families = await this.prisma.family.findMany({
      where: { deletedAt: null },
      select: { id: true },
    });

    let alarmsTriggered = 0;
    let alarmsEscalated = 0;
    let alarmsResolved = 0;
    const errors: string[] = [];

    for (const fam of families) {
      try {
        const result = await this.scanFamily(fam.id);
        alarmsTriggered += result.triggered;
        alarmsEscalated += result.escalated;
        alarmsResolved += result.resolved;
      } catch (err) {
        errors.push(`family ${fam.id}: ${err instanceof Error ? err.message : err}`);
      }
    }

    this.logger.log(
      `SilentAlarm: scan complete - families=${families.length}, triggered=${alarmsTriggered}, escalated=${alarmsEscalated}, resolved=${alarmsResolved}, errors=${errors.length}`,
    );

    return {
      familiesScanned: families.length,
      alarmsTriggered,
      alarmsEscalated,
      alarmsResolved,
      errors,
    };
  }

  /**
   * Scan a single family for inactive Persons.
   */
  async scanFamily(familyId: string): Promise<{
    triggered: number;
    escalated: number;
    resolved: number;
  }> {
    let triggered = 0;
    let escalated = 0;
    let resolved = 0;

    // 1. Find the family's bridge role (from MemberKinrelRole)
    const bridgeRole = await this.prisma.memberKinrelRole.findFirst({
      where: { familyId, roleKey: 'bridge' },
      select: { memberId: true },
    });

    // If no bridge role, fall back to the family owner
    let bridgeUserId: string | null = null;
    if (bridgeRole) {
      const bridgePerson = await this.prisma.person.findUnique({
        where: { id: bridgeRole.memberId },
        select: { linkedUserId: true },
      });
      bridgeUserId = bridgePerson?.linkedUserId ?? null;
    }
    if (!bridgeUserId) {
      // Fallback: family owner
      const owner = await this.prisma.familyMember.findFirst({
        where: { familyId, role: 'owner' },
        select: { userId: true },
      });
      bridgeUserId = owner?.userId ?? null;
    }
    if (!bridgeUserId) return { triggered: 0, escalated: 0, resolved: 0 };

    // 2. Get all active Persons in the family (excluding the bridge themselves)
    const persons = await this.prisma.person.findMany({
      where: {
        familyId,
        deletedAt: null,
        isDeceased: false,
      },
      select: {
        id: true,
        name: true,
        linkedUserId: true,
        updatedAt: true,
      },
    });

    const now = new Date();
    const msPerDay = 1000 * 60 * 60 * 24;

    for (const person of persons) {
      // Get the effective last-active time (User.updatedAt if linked, else Person.updatedAt)
      let lastActiveAt = person.updatedAt;
      if (person.linkedUserId) {
        const user = await this.prisma.user.findUnique({
          where: { id: person.linkedUserId },
          select: { updatedAt: true },
        });
        if (user) lastActiveAt = user.updatedAt;
      }

      const daysInactive = Math.floor((now.getTime() - lastActiveAt.getTime()) / msPerDay);

      // Check for existing alarm
      const existing = await this.prisma.silentAlarm.findFirst({
        where: {
          inactivePersonId: person.id,
          status: { in: ['triggered', 'acknowledged'] },
        },
      });

      // ?? Compute the severity from BOTH rules ??????????????????????????
      // (a) Absolute-floor rule (v1) - always applies
      const floorSeverity = this.floorSeverity(daysInactive);

      // (b) Adaptive per-person rule (v3) - only applies if the person has
      //     enough activity history to compute a meaningful baseline.
      //     We sample their recent "gaps between activity" by looking at
      //     the timestamps of their recent interactions (posts, sparqs,
      //     votes, comments). For now we approximate this by sampling
      //     User.updatedAt history, but the right long-term source is an
      //     activity log - see note in fetchPersonActivityGaps().
      let adaptiveSeverity: 'none' | 'gentle' | 'moderate' | 'urgent' = 'none';
      let adaptiveZ: number | undefined;
      let baselineMeanDays: number | undefined;
      try {
        const gaps = await this.fetchPersonActivityGaps(person.id, person.linkedUserId);
        if (gaps.length >= MIN_HISTORY_FOR_BASELINE) {
          const baseline = stats(gaps);
          if (baseline && baseline.stddev > 0) {
            const z = (daysInactive - baseline.mean) / baseline.stddev;
            if (z >= Z_SCORE_THRESHOLD) {
              adaptiveSeverity = this.adaptiveSeverity(z, daysInactive);
              adaptiveZ = z;
              baselineMeanDays = baseline.mean;
            }
          }
        }
      } catch (err) {
        // Don't let adaptive-rule failures block the floor-rule check
        this.logger.debug?.(
          `Adaptive baseline computation failed for person ${person.id}: ${(err as Error).message}`,
        );
      }

      // Max the two severities - the higher one wins.
      const severity = maxSeverity(floorSeverity, adaptiveSeverity);

      // If neither rule fires, the person is active (or below all thresholds
      // AND consistent with their baseline) - resolve any existing alarm.
      if (severity === 'none') {
        if (existing) {
          await this.prisma.silentAlarm.update({
            where: { id: existing.id },
            data: {
              status: 'resolved',
              resolvedAt: now,
            },
          });
          resolved++;
        }
        continue;
      }

      // Append an adaptive-context note to the alarm message when the
      // adaptive rule fired (so the bridge understands WHY this is being
      // flagged even if daysInactive < 7).
      const alarmMessage = this.buildAlarmMessage(
        person.name,
        daysInactive,
        severity,
        adaptiveSeverity !== 'none' && floorSeverity === 'none',
        adaptiveZ,
        baselineMeanDays,
      );
      const suggestions = SUGGESTIONS_BY_SEVERITY[severity] ?? SUGGESTIONS_BY_SEVERITY.gentle;

      if (existing) {
        // Update severity if it's escalated
        if (existing.severity !== severity) {
          await this.prisma.silentAlarm.update({
            where: { id: existing.id },
            data: {
              severity,
              daysInactive,
              alarmMessage,
              suggestions: suggestions as any,
              lastActiveAt,
              // If escalated to urgent and not yet escalated, mark it
              ...(severity === 'urgent' && existing.status !== 'escalated'
                ? { status: 'escalated', escalatedAt: now }
                : {}),
            },
          });
          escalated++;
        }
      } else {
        // Create new alarm
        await this.prisma.silentAlarm.create({
          data: {
            familyId,
            inactivePersonId: person.id,
            inactiveUserId: person.linkedUserId ?? null,
            bridgeUserId,
            daysInactive,
            lastActiveAt,
            severity,
            alarmMessage,
            suggestions: suggestions as any,
            status: 'triggered',
          },
        });
        triggered++;
      }
    }

    return { triggered, escalated, resolved };
  }

  // ?? Severity helpers ??????????????????????????????????????????????????????

  /**
   * v1 absolute-floor severity. Always applies - catches truly inactive
   * people regardless of their normal pattern.
   */
  private floorSeverity(daysInactive: number): 'none' | 'gentle' | 'moderate' | 'urgent' {
    if (daysInactive >= URGENT_THRESHOLD_DAYS) return 'urgent';
    if (daysInactive >= MODERATE_THRESHOLD_DAYS) return 'moderate';
    if (daysInactive >= GENTLE_THRESHOLD_DAYS) return 'gentle';
    return 'none';
  }

  /**
   * v3 adaptive severity. Maps a z-score to a severity tier. Higher z =
   * more unusual for this person -> higher severity.
   *
   * Note: adaptive severity is intentionally capped at 'moderate' for the
   * typical 2.5-3.5sigma band. The 'urgent' tier is reserved for the absolute
   * floor (21+ days) so that "unusual for them" never escalates past
   * 'moderate' on its own - only "truly inactive by absolute standards"
   * triggers urgent.
   */
  private adaptiveSeverity(z: number, daysInactive: number): 'none' | 'gentle' | 'moderate' | 'urgent' {
    // Even with adaptive, we still require a minimum absolute threshold
    // (3 days) before the adaptive rule can fire on its own. This prevents
    // a person whose baseline is "activity every few hours" from being
    // flagged as unusual-for-them just because they took a single weekend off.
    if (daysInactive < 3) return 'none';
    if (z >= 3.5) return 'moderate';
    if (z >= Z_SCORE_THRESHOLD) return 'gentle';
    return 'none';
  }

  // ?? Activity history ??????????????????????????????????????????????????????

  /**
   * Fetch the person's recent "gaps between activity" in days.
   *
   * We sample activity timestamps from multiple sources:
   *   - FamilyPost authored by the person's linked user
   *   - Sparq authored by the person's linked user
   *   - DecisionVote cast by the person's linked user
   *   - Comment authored by the person's linked user
   *   - Story authored by the person's linked user
   *
   * We then sort them descending (most recent first) and compute the gap
   * between each consecutive pair. The result is an array of gap-in-days
   * values, oldest gap first. The most recent gap (today - last activity)
   * is NOT included in the baseline - that's the value we're comparing
   * against the baseline.
   *
   * If the person has no linkedUserId, we fall back to Person.updatedAt
   * history - but Person.updatedAt only reflects edits to the Person row
   * itself, not actual user activity. In that case the baseline will be
   * sparse and the adaptive rule will mostly not fire (which is fine -
   // the floor rule still catches truly inactive people).
   */
  private async fetchPersonActivityGaps(
    personId: string,
    linkedUserId: string | null,
  ): Promise<number[]> {
    if (!linkedUserId) {
      // No linked user -> no real activity history. Return empty so the
      // adaptive rule can't fire (the floor rule still applies).
      return [];
    }

    // Gather activity timestamps from all sources. We take the most recent
    // MAX_BASELINE_SAMPLE_SIZE+1 from each source (so after merging + sorting
    // we still have enough samples). We use createdAt/updatedAt fields.
    const sampleSize = MAX_BASELINE_SAMPLE_SIZE + 1;
    const timestamps: Date[] = [];

    // FamilyPost
    try {
      const posts = await this.prisma.familyPost.findMany({
        where: { authorId: linkedUserId },
        orderBy: { createdAt: 'desc' },
        take: sampleSize,
        select: { createdAt: true },
      });
      timestamps.push(...posts.map((p) => p.createdAt));
    } catch {
      // table may not exist in some envs
    }

    // Sparq
    try {
      const sparqs = await this.prisma.sparq.findMany({
        where: { userId: linkedUserId },
        orderBy: { createdAt: 'desc' },
        take: sampleSize,
        select: { createdAt: true },
      });
      timestamps.push(...sparqs.map((s) => s.createdAt));
    } catch {
      // table may not exist
    }

    // DecisionVote
    try {
      const votes = await this.prisma.decisionVote.findMany({
        where: { userId: linkedUserId },
        orderBy: { votedAt: 'desc' },
        take: sampleSize,
        select: { votedAt: true },
      });
      timestamps.push(...votes.map((v) => v.votedAt));
    } catch {
      // table may not exist
    }

    // Comment
    try {
      const comments = await this.prisma.comment.findMany({
        where: { authorId: linkedUserId },
        orderBy: { createdAt: 'desc' },
        take: sampleSize,
        select: { createdAt: true },
      });
      timestamps.push(...comments.map((c) => c.createdAt));
    } catch {
      // table may not exist
    }

    // Story
    try {
      const stories = await this.prisma.story.findMany({
        where: { userId: linkedUserId },
        orderBy: { createdAt: 'desc' },
        take: sampleSize,
        select: { createdAt: true },
      });
      timestamps.push(...stories.map((s) => s.createdAt));
    } catch {
      // table may not exist
    }

    if (timestamps.length < 2) return [];

    // Sort descending (most recent first), dedupe, take top N+1
    const sorted = timestamps.sort((a, b) => b.getTime() - a.getTime());
    const unique: number[] = [];
    let last = -1;
    for (const t of sorted) {
      const ms = t.getTime();
      if (ms !== last) {
        unique.push(ms);
        last = ms;
      }
      if (unique.length >= MAX_BASELINE_SAMPLE_SIZE + 1) break;
    }

    // Compute gaps (in days) between consecutive timestamps. The most
    // recent gap (now - sorted[0]) is EXCLUDED - that's the value we're
    // comparing against the baseline, not part of the baseline itself.
    const msPerDay = 1000 * 60 * 60 * 24;
    const gaps: number[] = [];
    for (let i = 1; i < unique.length; i++) {
      const gapDays = (unique[i - 1] - unique[i]) / msPerDay;
      // Only count positive gaps (deduplication should prevent zeros, but
      // guard anyway)
      if (gapDays > 0) gaps.push(gapDays);
    }

    return gaps;
  }

  /** Get alarms for a bridge user (or family admin). */
  async getAlarmsForUser(userId: string) {
    // Get alarms where user is the bridge OR user is an admin of the family
    const bridgeAlarms = await this.prisma.silentAlarm.findMany({
      where: { bridgeUserId: userId, status: { in: ['triggered', 'acknowledged', 'escalated'] } },
      orderBy: { daysInactive: 'desc' },
      include: {
        inactivePerson: { select: { id: true, name: true, photoThumb: true } },
      },
    });

    // Also get escalated alarms for families where user is admin
    const adminMemberships = await this.prisma.familyMember.findMany({
      where: { userId, role: { in: ['owner', 'admin'] } },
      select: { familyId: true },
    });
    const adminFamilyIds = adminMemberships.map((m) => m.familyId);

    const escalatedAlarms = adminFamilyIds.length > 0
      ? await this.prisma.silentAlarm.findMany({
          where: {
            familyId: { in: adminFamilyIds },
            status: 'escalated',
            bridgeUserId: { not: userId }, // don't duplicate bridge alarms
          },
          orderBy: { daysInactive: 'desc' },
          include: {
            inactivePerson: { select: { id: true, name: true, photoThumb: true } },
          },
        })
      : [];

    const all = [...bridgeAlarms, ...escalatedAlarms];
    return all.map((a) => this.serializeAlarm(a));
  }

  /** Acknowledge an alarm (bridge says "I'll reach out"). */
  async acknowledgeAlarm(alarmId: string, userId: string) {
    const alarm = await this.prisma.silentAlarm.findUnique({
      where: { id: alarmId },
      select: { id: true, bridgeUserId: true, familyId: true },
    });
    if (!alarm) throw new Error('Alarm not found');

    // Verify access (bridge or admin)
    if (alarm.bridgeUserId !== userId) {
      const fm = await this.prisma.familyMember.findUnique({
        where: {
          familyId_userId: { familyId: alarm.familyId, userId },
        },
        select: { role: true },
      });
      if (!fm || !['owner', 'admin'].includes(fm.role)) {
        throw new Error('Not authorized to acknowledge this alarm');
      }
    }

    const updated = await this.prisma.silentAlarm.update({
      where: { id: alarmId },
      data: {
        status: 'acknowledged',
        acknowledgedAt: new Date(),
        acknowledgedById: userId,
      },
    });

    return { id: updated.id, status: updated.status };
  }

  // ????????????????????????????????????????????????????????????????????????
  // Helpers
  // ????????????????????????????????????????????????????????????????????????

  private buildAlarmMessage(
    name: string,
    daysInactive: number,
    severity: string,
    adaptiveOnly: boolean,
    adaptiveZ?: number,
    baselineMeanDays?: number,
  ): string {
    const daysWord = daysInactive === 1 ? '1 day' : `${daysInactive} days`;
    const adaptiveSuffix = adaptiveOnly && adaptiveZ !== undefined && baselineMeanDays !== undefined
      ? ` (This is unusual for ${name} - their typical gap is ${baselineMeanDays.toFixed(1)} days, this is ${adaptiveZ.toFixed(1)}sigma above.)`
      : '';

    if (severity === 'urgent') {
      return `${name} has been quiet for ${daysWord}. As the family bridge, you're the best person to reach out. Please check on them.`;
    }
    if (severity === 'moderate') {
      return `${name} hasn't been active in ${daysWord}${adaptiveSuffix}. A quick check-in from you would mean a lot.`;
    }
    return `${name} has been quiet for ${daysWord}${adaptiveSuffix}. Consider sending them a message.`;
  }

  private serializeAlarm(a: any) {
    return {
      id: a.id,
      familyId: a.familyId,
      inactivePersonId: a.inactivePersonId,
      inactivePerson: a.inactivePerson
        ? { id: a.inactivePerson.id, name: a.inactivePerson.name, photoThumb: a.inactivePerson.photoThumb }
        : null,
      bridgeUserId: a.bridgeUserId,
      daysInactive: a.daysInactive,
      lastActiveAt: a.lastActiveAt?.toISOString() ?? null,
      severity: a.severity,
      alarmMessage: a.alarmMessage,
      status: a.status,
      acknowledgedAt: a.acknowledgedAt?.toISOString() ?? null,
      resolvedAt: a.resolvedAt?.toISOString() ?? null,
      escalatedAt: a.escalatedAt?.toISOString() ?? null,
      suggestions: a.suggestions,
      createdAt: a.createdAt.toISOString(),
    };
  }
}

// ?? Pure statistics helpers (mirrors analytics.anomaly-detector.ts) ??????????

function stats(values: number[]): { count: number; mean: number; stddev: number } | undefined {
  if (values.length === 0) return undefined;
  const n = values.length;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  if (n < 2) return { count: n, mean, stddev: 0 };
  const variance = values.reduce((acc, v) => acc + (v - mean) ** 2, 0) / (n - 1);
  return { count: n, mean, stddev: Math.sqrt(variance) };
}

function maxSeverity(
  a: 'none' | 'gentle' | 'moderate' | 'urgent',
  b: 'none' | 'gentle' | 'moderate' | 'urgent',
): 'none' | 'gentle' | 'moderate' | 'urgent' {
  const order = { none: 0, gentle: 1, moderate: 2, urgent: 3 } as const;
  return order[a] >= order[b] ? a : b;
}
