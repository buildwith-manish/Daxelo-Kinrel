// server/src/modules/chat/bot-mini-apps.service.ts
//
// DAXELO KINREL — Tier 6 Feature 6.7: Mini-apps in chats — Service
//
// Issues signed initData tokens for bot mini-app launches. The token is
// HMAC-SHA256 signed with the BOT_MINIAPP_SECRET env var so the web-app
// can verify the user identity + chat context securely.
//
// The token payload (base64-encoded JSON, then signed):
//   {
//     botId, userId, familyId?, receiverId?, sessionId, issuedAt, expiresAt
//   }
//
// The web-app verifies the signature using the same secret (shared via
// env var on both sides) — if the signature matches, the user identity
// is authentic.

import { Injectable, BadRequestException, NotFoundException, ForbiddenException, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';
import * as crypto from 'crypto';

@Injectable()
export class BotMiniAppsService {
  private readonly logger = new Logger(BotMiniAppsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  /// Create a mini-app session + return the signed initData token.
  /// The web-app URL the Flutter client loads should include this token
  /// as a query param (e.g. ?initData=<token>) so the web-app can verify.
  async createSession(
    userId: string,
    params: { botId: string; familyId?: string | null; receiverId?: string | null },
  ) {
    const secret = this.config.get<string>('BOT_MINIAPP_SECRET');
    if (!secret) {
      return { error: 'no_secret_configured' as const,
        message: 'Set BOT_MINIAPP_SECRET env var to enable mini-app sessions.' };
    }

    if ((params.familyId != null) === (params.receiverId != null)) {
      throw new BadRequestException('Pass exactly one of familyId or receiverId');
    }

    const bot = await this.prisma.bot.findUnique({ where: { id: params.botId } });
    if (!bot) throw new NotFoundException('Bot not found');

    // Validate family membership OR DM self-presence.
    if (params.familyId) {
      const membership = await this.prisma.familyMember.findUnique({
        where: { familyId_userId: { familyId: params.familyId, userId } },
      });
      if (!membership) throw new ForbiddenException('Not a member of this family');
    }
    // For DMs, the caller is the user themselves — no extra check needed.

    // Create the session row.
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000); // 1h
    const id = `bmas_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;

    // Build the unsigned payload.
    const payload = {
      botId: params.botId,
      userId,
      familyId: params.familyId ?? null,
      receiverId: params.receiverId ?? null,
      sessionId: id,
      issuedAt: new Date().toISOString(),
      expiresAt: expiresAt.toISOString(),
    };
    const payloadJson = JSON.stringify(payload);
    const payloadB64 = Buffer.from(payloadJson, 'utf8').toString('base64url');

    // Sign with HMAC-SHA256.
    const signature = crypto
      .createHmac('sha256', secret)
      .update(payloadB64)
      .digest('hex');

    // The full initData token is `<payloadB64>.<signature>`.
    const initData = `${payloadB64}.${signature}`;

    // Persist the session (with the signed token).
    await this.prisma.botMiniAppSession.create({
      data: {
        id,
        botId: params.botId,
        userId,
        familyId: params.familyId ?? null,
        receiverId: params.receiverId ?? null,
        initData,
        expiresAt,
      },
    });

    return {
      sessionId: id,
      botId: params.botId,
      initData,
      expiresAt: expiresAt.toISOString(),
    };
  }

  /// Verify an initData token (called by the web-app via its own
  /// server-side, OR by us if we want to gate a follow-up action).
  /// Returns the decoded payload when valid; throws when tampered/expired.
  async verifyToken(initData: string): Promise<{
    botId: string;
    userId: string;
    familyId: string | null;
    receiverId: string | null;
    sessionId: string;
    issuedAt: string;
    expiresAt: string;
  }> {
    const secret = this.config.get<string>('BOT_MINIAPP_SECRET');
    if (!secret) {
      throw new BadRequestException('BOT_MINIAPP_SECRET not configured');
    }

    const parts = initData.split('.');
    if (parts.length !== 2) {
      throw new BadRequestException('Invalid initData format');
    }
    const [payloadB64, signature] = parts;

    // Recompute the signature + compare.
    const expected = crypto
      .createHmac('sha256', secret)
      .update(payloadB64)
      .digest('hex');
    if (signature !== expected) {
      throw new BadRequestException('Invalid initData signature');
    }

    let payload: any;
    try {
      payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
    } catch {
      throw new BadRequestException('Invalid initData payload');
    }

    // Check expiry.
    const expiresAt = new Date(payload.expiresAt);
    if (expiresAt < new Date()) {
      throw new BadRequestException('initData token expired');
    }

    return payload;
  }
}
