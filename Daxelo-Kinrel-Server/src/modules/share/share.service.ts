import {
  Injectable,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';
import { ConfigService } from '@nestjs/config';
import { CreateShareDto } from './dto/create-share.dto';
import { randomUUID } from 'crypto';

@Injectable()
export class ShareService {
  private readonly logger = new Logger(ShareService.name);
  private readonly appBaseUrl: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {
    this.appBaseUrl = this.configService.get<string>('NEXT_PUBLIC_APP_URL', 'https://daxelo.app');
  }

  // ── Create Shareable Link ─────────────────────────────────────────

  async createShareLink(userId: string, dto: CreateShareDto) {
    const token = randomUUID();
    const expiresAt = dto.expiresAt ? new Date(dto.expiresAt) : null;

    const shareableLink = await this.prisma.shareableLink.create({
      data: {
        token,
        cardType: dto.cardType,
        familyId: dto.familyId ?? null,
        personId: dto.personId ?? null,
        title: dto.title,
        description: dto.description,
        deepLinkUrl: dto.deepLinkUrl,
        expiresAt,
      },
    });

    const shareUrl = `${this.appBaseUrl}/api/share/${token}`;

    // Track the share event
    try {
      await this.prisma.whatsAppAnalytics.create({
        data: {
          event: 'whatsapp.card.shared',
          userId,
          familyId: dto.familyId ?? null,
          metadata: JSON.stringify({ shareToken: token, cardType: dto.cardType, personId: dto.personId }),
        },
      });
    } catch (err) {
      this.logger.error('Failed to track share event:', err);
    }

    return {
      shareableLink: {
        id: shareableLink.id,
        token: shareableLink.token,
        cardType: shareableLink.cardType,
        familyId: shareableLink.familyId,
        personId: shareableLink.personId,
        title: shareableLink.title,
        description: shareableLink.description,
        deepLinkUrl: shareableLink.deepLinkUrl,
        expiresAt: shareableLink.expiresAt,
        viewCount: shareableLink.viewCount,
        shareCount: shareableLink.shareCount,
        createdAt: shareableLink.createdAt,
      },
      shareUrl,
    };
  }

  // ── Get Share Stats ───────────────────────────────────────────────

  async getShareStats(token: string) {
    const shareableLink = await this.prisma.shareableLink.findUnique({
      where: { token },
      select: {
        id: true,
        token: true,
        cardType: true,
        title: true,
        viewCount: true,
        shareCount: true,
        expiresAt: true,
        createdAt: true,
      },
    });

    if (!shareableLink) throw new NotFoundException('Shareable link not found');

    const isExpired = shareableLink.expiresAt !== null && shareableLink.expiresAt < new Date();

    return {
      stats: {
        token: shareableLink.token,
        cardType: shareableLink.cardType,
        title: shareableLink.title,
        viewCount: shareableLink.viewCount,
        shareCount: shareableLink.shareCount,
        isExpired,
        createdAt: shareableLink.createdAt,
        expiresAt: shareableLink.expiresAt,
      },
    };
  }

  // ── Resolve Share Link ────────────────────────────────────────────

  async resolveShareLink(token: string): Promise<{ html: string }> {
    const shareableLink = await this.prisma.shareableLink.findUnique({
      where: { token },
    });

    if (!shareableLink) {
      return { html: JSON.stringify({ error: 'Shareable link not found' }) };
    }

    if (shareableLink.expiresAt && shareableLink.expiresAt < new Date()) {
      return { html: JSON.stringify({ error: 'This shareable link has expired' }) };
    }

    // Increment view count (fire-and-forget)
    this.prisma.shareableLink
      .update({ where: { id: shareableLink.id }, data: { viewCount: { increment: 1 } } })
      .catch((err) => this.logger.error('Failed to increment view count:', err));

    const ogImageUrl = `${this.appBaseUrl}/api/share/${token}/card`;
    const ogTitle = shareableLink.title;
    const ogDescription = shareableLink.description;

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${escapeHtml(ogTitle)}</title>
  <meta http-equiv="refresh" content="0;url=${escapeHtml(shareableLink.deepLinkUrl)}" />
  <meta property="og:title" content="${escapeHtml(ogTitle)}" />
  <meta property="og:description" content="${escapeHtml(ogDescription)}" />
  <meta property="og:image" content="${escapeHtml(ogImageUrl)}" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:type" content="website" />
  <meta property="og:url" content="${escapeHtml(`${this.appBaseUrl}/api/share/${token}`)}" />
  <meta property="og:site_name" content="Daxelo Kinrel" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${escapeHtml(ogTitle)}" />
  <meta name="twitter:description" content="${escapeHtml(ogDescription)}" />
  <meta name="twitter:image" content="${escapeHtml(ogImageUrl)}" />
  <style>
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;background:#FFF7ED;color:#1C1917}
    .container{text-align:center;padding:2rem;max-width:480px}
    .spinner{width:40px;height:40px;border:3px solid #F97316;border-top-color:transparent;border-radius:50%;animation:spin .8s linear infinite;margin:0 auto 1.5rem}
    @keyframes spin{to{transform:rotate(360deg)}}
    h1{font-size:1.25rem;font-weight:700;margin-bottom:.5rem}
    p{font-size:.875rem;color:#57534E}
    a{display:inline-block;margin-top:1.5rem;padding:.75rem 1.5rem;background:#F97316;color:#FFF;border-radius:8px;text-decoration:none;font-weight:600;font-size:.875rem}
  </style>
</head>
<body>
  <div class="container">
    <div class="spinner"></div>
    <h1>Opening Daxelo Kinrel...</h1>
    <p>You're being redirected to the app. If nothing happens, tap the button below.</p>
    <a href="${escapeHtml(shareableLink.deepLinkUrl)}">Open in Daxelo Kinrel</a>
  </div>
</body>
</html>`;

    return { html };
  }
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}
