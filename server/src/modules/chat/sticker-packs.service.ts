// server/src/modules/chat/sticker-packs.service.ts
//
// DAXELO KINREL — Tier 4 Features 4.4 + 4.5: Sticker packs from photos
// + Animated stickers — Service
//
// CRUD for the user's own sticker packs. Each pack can contain a mix of
// static (PNG/WebP) and animated (Lottie JSON/TGS) stickers. Packs sync
// across the user's devices via Supabase Realtime on UserStickerPack +
// UserStickerItem tables.
//
// The "Make sticker" flow (long-press a photo → background-removal →
// save to "My Stickers" pack) is the Flutter side; this service is the
// persistence layer the Flutter client calls.

import { Injectable, BadRequestException, NotFoundException, ForbiddenException, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class StickerPacksService {
  private readonly logger = new Logger(StickerPacksService.name);

  constructor(private readonly prisma: PrismaService) {}

  /// List all the caller's packs + their items in a single query (the
  /// Flutter picker loads everything at once on first open). The default
  /// "My Stickers" pack appears first.
  async listMyPacks(userId: string) {
    const packs = await this.prisma.userStickerPack.findMany({
      where: { ownerId: userId },
      include: { items: { orderBy: { createdAt: 'asc' } } },
      orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
    });
    return packs;
  }

  /// Create a new sticker pack (NOT the default "My Stickers" pack —
  /// the default pack is auto-created via fn_ensure_default_sticker_pack
  /// RPC; this service is for named packs the user creates explicitly).
  async createPack(
    userId: string,
    params: { name: string; thumbUrl?: string | null; isAnimated?: boolean },
  ) {
    const name = params.name?.trim();
    if (!name) throw new BadRequestException('Pack name is required');
    if (name.length > 50) throw new BadRequestException('Pack name must be at most 50 characters');

    const id = `usp_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    return this.prisma.userStickerPack.create({
      data: {
        id,
        ownerId: userId,
        name,
        thumbUrl: params.thumbUrl ?? null,
        isAnimated: params.isAnimated ?? false,
        isDefault: false,
      },
      include: { items: true },
    });
  }

  async updatePack(
    userId: string,
    packId: string,
    params: { name?: string; thumbUrl?: string | null },
  ) {
    const existing = await this.prisma.userStickerPack.findUnique({ where: { id: packId } });
    if (!existing) throw new NotFoundException('Pack not found');
    if (existing.ownerId !== userId) throw new ForbiddenException('Not the owner of this pack');
    if (existing.isDefault && params.name !== undefined) {
      throw new BadRequestException('Cannot rename the default pack');
    }
    const data: any = {};
    if (params.name !== undefined) {
      const name = params.name.trim();
      if (!name) throw new BadRequestException('Pack name cannot be empty');
      data.name = name;
    }
    if (params.thumbUrl !== undefined) data.thumbUrl = params.thumbUrl;
    return this.prisma.userStickerPack.update({ where: { id: packId }, data, include: { items: true } });
  }

  async deletePack(userId: string, packId: string) {
    const existing = await this.prisma.userStickerPack.findUnique({ where: { id: packId } });
    if (!existing) throw new NotFoundException('Pack not found');
    if (existing.ownerId !== userId) throw new ForbiddenException('Not the owner of this pack');
    if (existing.isDefault) {
      throw new BadRequestException('Cannot delete the default pack — it can only be emptied');
    }
    await this.prisma.userStickerPack.delete({ where: { id: packId } });
    return { success: true, deleted: packId };
  }

  /// Add a sticker to a pack. The Flutter "Make sticker" flow uploads
  /// the processed image to Supabase Storage + passes the resulting URL
  /// to this endpoint.
  async addSticker(
    userId: string,
    packId: string,
    params: {
      stickerName: string;
      imageUrl: string;
      isAnimated?: boolean;
      lottieUrl?: string | null;
      emoji?: string | null;
    },
  ) {
    const pack = await this.prisma.userStickerPack.findUnique({ where: { id: packId } });
    if (!pack) throw new NotFoundException('Pack not found');
    if (pack.ownerId !== userId) throw new ForbiddenException('Not the owner of this pack');

    if (!params.stickerName?.trim()) throw new BadRequestException('stickerName is required');
    if (!params.imageUrl?.trim()) throw new BadRequestException('imageUrl is required');
    if (params.isAnimated && !params.lottieUrl?.trim()) {
      throw new BadRequestException('lottieUrl is required when isAnimated=true');
    }

    const id = `usi_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    return this.prisma.userStickerItem.create({
      data: {
        id,
        packId,
        stickerName: params.stickerName.trim(),
        imageUrl: params.imageUrl,
        isAnimated: params.isAnimated ?? false,
        lottieUrl: params.lottieUrl ?? null,
        emoji: params.emoji ?? null,
      },
    });
  }

  async removeSticker(userId: string, stickerId: string) {
    // Verify ownership via the parent pack.
    const sticker = await this.prisma.userStickerItem.findUnique({
      where: { id: stickerId },
      include: { pack: { select: { ownerId: true } } },
    });
    if (!sticker) throw new NotFoundException('Sticker not found');
    if (sticker.pack.ownerId !== userId) throw new ForbiddenException('Not the owner of this sticker');
    await this.prisma.userStickerItem.delete({ where: { id: stickerId } });
    return { success: true, deleted: stickerId };
  }

  /// Ensure the caller has the default "My Stickers" pack — created on
  /// first call. Used by the Flutter client on sticker picker first open.
  async ensureDefaultPack(userId: string) {
    const existing = await this.prisma.userStickerPack.findFirst({
      where: { ownerId: userId, isDefault: true },
    });
    if (existing) return existing;
    const id = `usp_default_${userId}`;
    return this.prisma.userStickerPack.create({
      data: {
        id,
        ownerId: userId,
        name: 'My Stickers',
        isAnimated: false,
        isDefault: true,
      },
      include: { items: true },
    });
  }
}
