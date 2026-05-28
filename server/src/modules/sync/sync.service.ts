import { Injectable, Logger, BadRequestException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

/**
 * SyncService — Handles incremental data synchronization for offline-capable clients.
 *
 * The sync endpoint returns all data modified after a given timestamp,
 * enabling clients to stay up-to-date without downloading the full dataset.
 *
 * Response constraints:
 *  - Max 100 records per sync response
 *  - Response must be under 50KB for slow networks
 *  - If hasMore=true, client should sync again with the new serverTime
 */
@Injectable()
export class SyncService {
  private readonly logger = new Logger(SyncService.name);
  private readonly MAX_RECORDS = 100;
  private readonly MAX_RESPONSE_SIZE_BYTES = 50 * 1024; // 50KB

  constructor(private prisma: PrismaService) {}

  /**
   * Perform an incremental sync for a user.
   *
   * @param since ISO timestamp — only records with updatedAt > since will be returned
   * @param userId The authenticated user's ID
   * @returns Sync response with members, events, familyMeta, serverTime, hasMore
   */
  async sync(since: string | undefined, userId: string) {
    // Parse the `since` timestamp
    const sinceDate = since ? new Date(since) : new Date(0); // epoch = first sync

    if (since && isNaN(sinceDate.getTime())) {
      throw new BadRequestException('Invalid "since" timestamp. Must be a valid ISO 8601 date string.');
    }

    // Get all family IDs the user belongs to
    const memberships = await this.prisma.familyMember.findMany({
      where: { userId },
      select: { familyId: true },
    });
    const familyIds = memberships.map((m) => m.familyId);

    if (familyIds.length === 0) {
      return this.emptySyncResponse();
    }

    // ── Fetch modified members (Person records) ───────────────
    const members = await this.prisma.person.findMany({
      where: {
        familyId: { in: familyIds },
        updatedAt: { gt: sinceDate },
      },
      orderBy: { updatedAt: 'asc' },
      take: this.MAX_RECORDS,
      select: {
        id: true,
        familyId: true,
        name: true,
        gender: true,
        dateOfBirth: true,
        gotra: true,
        occupation: true,
        city: true,
        isDeceased: true,
        privacyLevel: true,
        deletedAt: true,
        birthYear: true,
        notes: true,
        sideOfFamily: true,
        generationIndex: true,
        isAnchor: true,
        photoUrl: true,
        username: true,
        updatedAt: true,
      },
    });

    // ── Fetch modified events (FamilyPost records) ────────────
    const remainingCapacity = this.MAX_RECORDS - members.length;
    const events = remainingCapacity > 0
      ? await this.prisma.familyPost.findMany({
          where: {
            familyId: { in: familyIds },
            updatedAt: { gt: sinceDate },
          },
          orderBy: { updatedAt: 'asc' },
          take: remainingCapacity,
          select: {
            id: true,
            familyId: true,
            authorId: true,
            postType: true,
            content: true,
            reactions: true,
            createdAt: true,
            updatedAt: true,
          },
        })
      : [];

    // ── Fetch modified family metadata ────────────────────────
    const familyMetaArray = await this.prisma.family.findMany({
      where: {
        id: { in: familyIds },
        updatedAt: { gt: sinceDate },
      },
      select: {
        id: true,
        name: true,
        familyCode: true,
        username: true,
        description: true,
        primaryLanguage: true,
        gotra: true,
        originVillage: true,
        privacyMode: true,
        anchorPersonId: true,
        memberCount: true,
        generationCount: true,
        avatarUrl: true,
        region: true,
        isOnboarded: true,
        updatedAt: true,
      },
    });

    // Convert familyMetaArray to a single object keyed by familyId
    const familyMeta: Record<string, any> = {};
    for (const f of familyMetaArray) {
      familyMeta[f.id] = f;
    }

    // ── Determine if there's more data ────────────────────────
    const serverTime = new Date().toISOString();

    // Check if there are more records beyond what we fetched
    const totalModified = members.length + events.length;
    const hasMore = totalModified >= this.MAX_RECORDS;

    // Check response size constraint (rough estimation)
    const responsePayload = { members, events, familyMeta, serverTime, hasMore: false };
    const estimatedSize = JSON.stringify(responsePayload).length;

    // If the response would exceed 50KB, truncate and set hasMore
    if (estimatedSize > this.MAX_RESPONSE_SIZE_BYTES) {
      // Truncate members to fit within size limit
      const truncatedMembers = this.truncateToFit(members, events, familyMeta, serverTime);
      return {
        members: truncatedMembers.members,
        events: truncatedMembers.events,
        familyMeta,
        serverTime,
        hasMore: true,
      };
    }

    return {
      members,
      events,
      familyMeta,
      serverTime,
      hasMore,
    };
  }

  /**
   * Truncate records to fit within the 50KB response size limit.
   */
  private truncateToFit(
    members: any[],
    events: any[],
    familyMeta: Record<string, any>,
    serverTime: string,
  ): { members: any[]; events: any[] } {
    // Start with all members and progressively remove from the end
    for (let i = members.length; i > 0; i--) {
      const payload = {
        members: members.slice(0, i),
        events: [],
        familyMeta,
        serverTime,
        hasMore: true,
      };
      if (JSON.stringify(payload).length <= this.MAX_RESPONSE_SIZE_BYTES) {
        // Try to add some events too
        let eventCount = 0;
        for (let j = 1; j <= events.length; j++) {
          const testPayload = {
            members: members.slice(0, i),
            events: events.slice(0, j),
            familyMeta,
            serverTime,
            hasMore: true,
          };
          if (JSON.stringify(testPayload).length <= this.MAX_RESPONSE_SIZE_BYTES) {
            eventCount = j;
          } else {
            break;
          }
        }
        return {
          members: members.slice(0, i),
          events: events.slice(0, eventCount),
        };
      }
    }

    return { members: [], events: [] };
  }

  /**
   * Return an empty sync response for users with no families.
   */
  private emptySyncResponse() {
    return {
      members: [],
      events: [],
      familyMeta: {},
      serverTime: new Date().toISOString(),
      hasMore: false,
    };
  }
}
