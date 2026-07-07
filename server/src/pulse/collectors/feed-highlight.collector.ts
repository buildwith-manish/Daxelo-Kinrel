// server/src/pulse/collectors/feed-highlight.collector.ts
//
// FeedHighlightCollector — finds top FamilyPosts from the last 24h that the
// user hasn't reacted to yet.
//
// Strategy:
//   1. Query FamilyPost rows where:
//        - familyId = ctx.familyId
//        - createdAt > now - 24h
//        - authorId != ctx.userPersonId (don't show user their own posts)
//   2. For each post, parse the `reactions` JSON to check if the user has reacted.
//      The reactions JSON shape is: { heart: <count>, comment: <count>, isHearted: <bool>, isSaved: <bool> }
//      Note: this is a denormalized per-post field, NOT a per-user reaction record,
//      so we cannot reliably tell if THIS user reacted. We use a different signal:
//      we check the BriefInteraction table to see if the user already interacted
//      with a brief_item that had targetPostId = this post. If yes → skip.
//   3. Sort by reactions.heart DESC (most-loved posts first), then by recency.
//   4. Cap at 2 items.
//   5. Title: "{Author name} shared {postType}" or "{N} reactions to {author}'s post"
//   6. Body: short description from content JSON if available.
//
// Note on the "isHearted" field: it's a per-post flag indicating whether the
// *currently authenticated* user (when the post was loaded) hearted it. We can't
// use it here because the brief runs server-side without a per-user view. So we
// use the BriefInteraction skip-logic instead, which is more reliable.

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import {
  BriefCollector,
  BriefCollectorContext,
  BriefItemData,
  localizeAction,
} from '../brief-types';

const FEED_HORIZON_HOURS = 24;
const MAX_FEED_ITEMS = 2;

const POST_TYPE_LABELS: Record<string, string> = {
  relationship_discovered: 'a new family connection',
  member_joined: 'a new family member',
  milestone: 'a family milestone',
  connection_added: 'a new connection',
  invite_shared: 'a family invite',
};

interface ParsedReactions {
  heart?: number;
  comment?: number;
  isHearted?: boolean;
  isSaved?: boolean;
}

function parseReactions(raw: unknown): ParsedReactions {
  if (typeof raw === 'string') {
    try {
      return JSON.parse(raw) as ParsedReactions;
    } catch {
      return {};
    }
  }
  if (raw && typeof raw === 'object') {
    return raw as ParsedReactions;
  }
  return {};
}

interface ParsedContent {
  title?: string;
  description?: string;
  photoCount?: number;
  [k: string]: unknown;
}

function parseContent(raw: unknown): ParsedContent {
  if (typeof raw === 'string') {
    try {
      return JSON.parse(raw) as ParsedContent;
    } catch {
      return {};
    }
  }
  if (raw && typeof raw === 'object') {
    return raw as ParsedContent;
  }
  return {};
}

@Injectable()
export class FeedHighlightCollector implements BriefCollector {
  readonly name = 'feed_highlight';
  private readonly logger = new Logger(FeedHighlightCollector.name);

  constructor(private readonly prisma: PrismaService) {}

  async collect(ctx: BriefCollectorContext): Promise<BriefItemData[]> {
    try {
      const since = new Date(Date.now() - FEED_HORIZON_HOURS * 60 * 60 * 1000);

      // 1. Load recent posts (excluding user's own posts)
      const posts = await this.prisma.familyPost.findMany({
        where: {
          familyId: ctx.familyId,
          createdAt: { gt: since },
          ...(ctx.userPersonId ? { authorId: { not: ctx.userPersonId } } : {}),
        },
        select: {
          id: true,
          authorId: true,
          postType: true,
          content: true,
          reactions: true,
          createdAt: true,
          author: { select: { id: true, name: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: 20,
      });

      if (posts.length === 0) return [];

      // 2. Find which posts the user has already interacted with via brief items
      //    (BriefInteraction rows where briefItem.targetPostId = post.id and userId = ctx.userId)
      const alreadyInteractedPostIds = new Set<string>();
      const interactions = await this.prisma.briefItem.findMany({
        where: {
          userId: ctx.userId,
          targetPostId: { in: posts.map((p) => p.id) },
          interactedAt: { not: null },
        },
        select: { targetPostId: true },
      });
      for (const i of interactions) {
        if (i.targetPostId) alreadyInteractedPostIds.add(i.targetPostId);
      }

      // 3. Filter out already-interacted posts
      const candidates = posts.filter((p) => !alreadyInteractedPostIds.has(p.id));
      if (candidates.length === 0) return [];

      // 4. Score by reactions.heart DESC, then recency
      const scored = candidates
        .map((p) => {
          const reactions = parseReactions(p.reactions);
          const heartCount = typeof reactions.heart === 'number' ? reactions.heart : 0;
          return { post: p, heartCount };
        })
        .sort((a, b) => {
          if (b.heartCount !== a.heartCount) return b.heartCount - a.heartCount;
          return b.post.createdAt.getTime() - a.post.createdAt.getTime();
        });

      const top = scored.slice(0, MAX_FEED_ITEMS);

      // 5. Build items
      return top.map(({ post, heartCount }) => {
        const content = parseContent(post.content);
        const authorName = post.author?.name ?? 'Someone';
        const postTypeLabel = POST_TYPE_LABELS[post.postType] ?? 'a family update';
        const hoursAgo = Math.max(
          1,
          Math.round((Date.now() - post.createdAt.getTime()) / (60 * 60 * 1000)),
        );
        const photoClause = content.photoCount
          ? ` · ${content.photoCount} photo${content.photoCount === 1 ? '' : 's'}`
          : '';
        const heartClause = heartCount > 0 ? ` · ${heartCount} ❤️` : '';

        const title = `${authorName} shared ${postTypeLabel}`;
        const body =
          content.description ??
          content.title ??
          `${hoursAgo}h ago${photoClause}${heartClause}`;

        return {
          itemType: 'feed_highlight' as const,
          priority: 60,
          title,
          body,
          actionLabel: localizeAction('view_post', ctx.userLanguageCode),
          actionType: 'view_post' as const,
          actionData: {
            postId: post.id,
            authorId: post.authorId,
            authorName,
            postType: post.postType,
            createdAt: post.createdAt.toISOString(),
            heartCount,
          },
          targetPostId: post.id,
          ...(post.authorId ? { targetPersonId: post.authorId } : {}),
          relevanceScore: 0.55,
        };
      });
    } catch (err) {
      this.logger.error(
        `FeedHighlightCollector failed for family ${ctx.familyId}: ${err instanceof Error ? err.message : err}`,
      );
      return [];
    }
  }
}
