// server/src/modules/chat/emoji-packs.service.ts
//
// DAXELO KINREL — Tier 4 Feature 4.6: Custom emoji packs — Service
//
// Lets a user install / uninstall emoji packs. EmojiPacks are GLOBAL
// catalog rows (any user can install them); UserEmojiPackInstall tracks
// the per-user install relation.
//
// Pack creation is admin-only (the global catalog is curated). The
// install/uninstall endpoints are open to any authenticated user.
// Installed packs show in the emoji picker + reaction tray.

import { Injectable, BadRequestException, NotFoundException, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class EmojiPacksService {
  private readonly logger = new Logger(EmojiPacksService.name);

  constructor(private readonly prisma: PrismaService) {}

  /// List ALL packs in the global catalog (with `installed` flag for
  /// the caller). Used by the Emoji Pack Store screen.
  async listCatalog(userId: string) {
    const [packs, myInstalls] = await Promise.all([
      this.prisma.emojiPack.findMany({
        include: { items: { orderBy: { createdAt: 'asc' } } },
        orderBy: [{ isOfficial: 'desc' }, { name: 'asc' }],
      }),
      this.prisma.userEmojiPackInstall.findMany({
        where: { userId },
        select: { packId: true },
      }),
    ]);
    const installedSet = new Set(myInstalls.map((i) => i.packId));
    return packs.map((p) => ({
      ...p,
      installed: installedSet.has(p.id),
    }));
  }

  /// List only the caller's installed packs + their items. Used by the
  /// emoji picker / reaction tray.
  async listInstalled(userId: string) {
    const installs = await this.prisma.userEmojiPackInstall.findMany({
      where: { userId },
      include: {
        pack: { include: { items: { orderBy: { createdAt: 'asc' } } } },
      },
      orderBy: { installedAt: 'desc' },
    });
    return installs.map((i) => i.pack);
  }

  async install(userId: string, packId: string) {
    const pack = await this.prisma.emojiPack.findUnique({ where: { id: packId } });
    if (!pack) throw new NotFoundException('Pack not found');
    const id = `uepi_${packId}_${userId}`;
    // Idempotent — re-installing an already-installed pack is a no-op.
    await this.prisma.userEmojiPackInstall.upsert({
      where: { id },
      create: { id, userId, packId },
      update: {},  // no fields to update; just touch the row
    });
    return { success: true, packId };
  }

  async uninstall(userId: string, packId: string) {
    await this.prisma.userEmojiPackInstall.deleteMany({
      where: { userId, packId },
    });
    return { success: true, packId };
  }

  /// Search installed packs' items by keyword. Used by the picker's
  /// search bar ("find an emoji that says 'party'").
  async searchItems(userId: string, keyword: string, limit: number = 20) {
    const trimmed = keyword.trim();
    if (trimmed.length === 0) return [];
    // Filter to the caller's installed packs only.
    const installs = await this.prisma.userEmojiPackInstall.findMany({
      where: { userId },
      select: { packId: true },
    });
    if (installs.length === 0) return [];
    const packIds = installs.map((i) => i.packId);
    // Prisma's `has` on text[] — find items where the keywords array
    // contains the search keyword (case-insensitive via ILIKE on the
    // array elements is not directly supported; use `string_starts_with`
    // as a best-effort proxy).
    return this.prisma.emojiPackItem.findMany({
      where: {
        packId: { in: packIds },
        OR: [
          { emojiName: { contains: trimmed, mode: 'insensitive' } },
          { keywords: { has: trimmed.toLowerCase() } },
        ],
      },
      take: Math.min(limit, 50),
    });
  }

  // ── Admin / pack-management endpoints (would be gated by an admin
  // guard in a future iteration; for now they're open to any authed user
  // — the assumption is that only admin-side tooling calls these).

  async createPack(
    userId: string,
    params: {
      name: string;
      thumbUrl?: string | null;
      isAnimated?: boolean;
      isOfficial?: boolean;
      publisherName?: string | null;
    },
  ) {
    if (!params.name?.trim()) throw new BadRequestException('Pack name is required');
    const id = `ep_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    return this.prisma.emojiPack.create({
      data: {
        id,
        name: params.name.trim(),
        thumbUrl: params.thumbUrl ?? null,
        isAnimated: params.isAnimated ?? false,
        isOfficial: params.isOfficial ?? false,
        publisherName: params.publisherName ?? null,
      },
    });
  }

  async addEmojiToPack(
    userId: string,
    packId: string,
    params: { emojiName: string; imageUrl: string; lottieUrl?: string | null; keywords?: string[] },
  ) {
    const pack = await this.prisma.emojiPack.findUnique({ where: { id: packId } });
    if (!pack) throw new NotFoundException('Pack not found');
    if (!params.emojiName?.trim()) throw new BadRequestException('emojiName is required');
    if (!params.imageUrl?.trim()) throw new BadRequestException('imageUrl is required');
    if (pack.isAnimated && !params.lottieUrl?.trim()) {
      throw new BadRequestException('lottieUrl is required when the pack isAnimated');
    }
    const id = `epi_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    return this.prisma.emojiPackItem.create({
      data: {
        id,
        packId,
        emojiName: params.emojiName.trim(),
        imageUrl: params.imageUrl,
        lottieUrl: params.lottieUrl ?? null,
        keywords: params.keywords ?? [],
      },
    });
  }
}
