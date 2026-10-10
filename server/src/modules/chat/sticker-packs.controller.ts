// server/src/modules/chat/sticker-packs.controller.ts
//
// DAXELO KINREL — Tier 4 Features 4.4 + 4.5: Sticker packs — Controller

import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { StickerPacksService } from './sticker-packs.service';

@Controller('chat/sticker-packs')
@UseGuards(JwtAuthGuard)
export class StickerPacksController {
  constructor(private readonly service: StickerPacksService) {}

  /// GET /chat/sticker-packs
  /// List all the caller's packs + items.
  @Get()
  async list(@CurrentUser('id') userId: string) {
    return this.service.listMyPacks(userId);
  }

  /// POST /chat/sticker-packs/ensure-default
  /// Create the default "My Stickers" pack if it doesn't exist.
  @Post('ensure-default')
  async ensureDefault(@CurrentUser('id') userId: string) {
    return this.service.ensureDefaultPack(userId);
  }

  /// POST /chat/sticker-packs
  /// Create a new named pack.
  @Post()
  async create(
    @CurrentUser('id') userId: string,
    @Body() body: { name: string; thumbUrl?: string | null; isAnimated?: boolean },
  ) {
    return this.service.createPack(userId, body);
  }

  /// PATCH /chat/sticker-packs/:id
  @Patch(':id')
  async update(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
    @Body() body: { name?: string; thumbUrl?: string | null },
  ) {
    return this.service.updatePack(userId, id, body);
  }

  /// DELETE /chat/sticker-packs/:id
  @Delete(':id')
  async delete(@CurrentUser('id') userId: string, @Param('id') id: string) {
    return this.service.deletePack(userId, id);
  }

  /// POST /chat/sticker-packs/:packId/stickers
  /// Add a sticker to a pack.
  @Post(':packId/stickers')
  async addSticker(
    @CurrentUser('id') userId: string,
    @Param('packId') packId: string,
    @Body() body: {
      stickerName: string;
      imageUrl: string;
      isAnimated?: boolean;
      lottieUrl?: string | null;
      emoji?: string | null;
    },
  ) {
    return this.service.addSticker(userId, packId, body);
  }

  /// DELETE /chat/sticker-packs/stickers/:stickerId
  @Delete('stickers/:stickerId')
  async removeSticker(
    @CurrentUser('id') userId: string,
    @Param('stickerId') stickerId: string,
  ) {
    return this.service.removeSticker(userId, stickerId);
  }
}
