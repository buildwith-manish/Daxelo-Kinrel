// server/src/emotional_attachment/silent-alarm.service.ts
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

// P1.4: Removed adaptive z-score baseline (the three constants that
// controlled per-person behavioral tracking). The z-score rule flagged
// people for "unusual-for-them" inactivity even below the 7-day absolute
// floor — this is behavioral baseline tracking applied to family
// relationships. Only the absolute floor (7/14/21 days) remains.
// See Vision §2.9 MEDIUM-HIGH.

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
   * Called at 6am IST by EmotionalAttachmentCronService.
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

    // P1.4: Check if the family has opted in to the bridge role. If not,
    // alarms are still generated (for admin visibility) but the bridge is
    // NOT notified. Only admins see the alarm. Default OFF — no surveillance
    // without explicit family opt-in.
    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      select: { bridgeRoleOptIn: true },
    });
    const bridgeOptedIn = family?.bridgeRoleOptIn ?? false;

    // 1. Find the family's bridge role (from MemberKinrelRole).
    // P1.4: Only look up the bridge role if the family has opted in.
    // If not opted in, fall back to the family owner as the alarm recipient
    // (for admin visibility). The bridge is not notified.
    let bridgeUserId: string | null = null;
    if (bridgeOptedIn) {
      const bridgeRole = await this.prisma.memberKinrelRole.findFirst({
        where: { familyId, roleKey: 'bridge' },
        select: { memberId: true },
      });

      if (bridgeRole) {
        const bridgePerson = await this.prisma.person.findUnique({
          where: { id: bridgeRole.memberId },
          select: { linkedUserId: true },
        });
        bridgeUserId = bridgePerson?.linkedUserId ?? null;
      }
    }
    // Fallback: family owner (always set so the alarm record has a valid
    // bridgeUserId for admin visibility, even when bridge role is off).
    if (!bridgeUserId) {
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

      // ?? Compute severity from the absolute-floor rule only ????????????
      // P1.4: Removed adaptive z-score baseline. Only the absolute floor
      // (7/14/21 days) determines severity. No behavioral baseline tracking.
      const severity = this.floorSeverity(daysInactive);

      // If below all thresholds, the person is active - resolve any alarm.
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

      // P1.4: buildAlarmMessage no longer takes adaptive params (z-score removed).
      const alarmMessage = this.buildAlarmMessage(
        person.name,
        daysInactive,
        severity,
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
            inactiveUserId: person.linkedUserId ?? undefined,
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
   *
   * P1.4: This is the SOLE severity rule. The adaptive z-score baseline
   * was removed per Vision §2.9 MEDIUM-HIGH. Only absolute inactivity
   * floors remain (7/14/21 days).
   */
  private floorSeverity(daysInactive: number): 'none' | 'gentle' | 'moderate' | 'urgent' {
    if (daysInactive >= URGENT_THRESHOLD_DAYS) return 'urgent';
    if (daysInactive >= MODERATE_THRESHOLD_DAYS) return 'moderate';
    if (daysInactive >= GENTLE_THRESHOLD_DAYS) return 'gentle';
    return 'none';
  }

  // P1.4: Removed adaptiveSeverity() method + fetchPersonActivityGaps() method.
  // The z-score baseline tracked "unusual-for-them" inactivity — behavioral
  // surveillance applied to family relationships. Only the absolute floor
  // remains.

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
  ): string {
    const daysWord = daysInactive === 1 ? '1 day' : `${daysInactive} days`;

    // P1.4: Removed adaptive-context suffix (z-score baseline removed).
    // Only absolute-floor severity determines the message.
    if (severity === 'urgent') {
      return `${name} has been quiet for ${daysWord}. As the family bridge, you're the best person to reach out. Please check on them.`;
    }
    if (severity === 'moderate') {
      return `${name} hasn't been active in ${daysWord}. A quick check-in from you would mean a lot.`;
    }
    return `${name} has been quiet for ${daysWord}. Consider sending them a message.`;
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

// P1.4: Removed stats() and maxSeverity() helpers — the adaptive z-score
// baseline that used them was removed. Only the absolute-floor rule remains.
