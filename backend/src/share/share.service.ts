import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateShareableLinkDto } from './dto/create-shareable-link.dto';
import { randomUUID } from 'crypto';

@Injectable()
export class ShareService {
  constructor(private prisma: PrismaService) {}

  /**
   * POST /api/share — Create a new shareable link
   */
  async createShareableLink(userId: string, dto: CreateShareableLinkDto) {
    // Generate a unique token for the shareable link
    const token = randomUUID();

    // Parse optional expiration date
    const expiresAt = dto.expiresAt ? new Date(dto.expiresAt) : null;

    // Create the shareable link record
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

    // Generate the share card URL for OG previews
    const appBaseUrl = process.env.NEXT_PUBLIC_APP_URL ?? 'https://daxelo.app';
    const shareUrl = `${appBaseUrl}/share/${token}`;

    // Track the share event
    await this.prisma.whatsAppAnalytics.create({
      data: {
        event: 'invite:whatsapp_share',
        userId,
        familyId: dto.familyId ?? null,
        metadata: JSON.stringify({
          shareToken: token,
          cardType: dto.cardType,
          personId: dto.personId,
        }),
      },
    }).catch((err) => {
      console.error('[Share POST] Failed to track share event:', err);
    });

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

  /**
   * GET /api/share?token=xxx — Get share stats
   */
  async getShareStats(token: string) {
    if (!token) {
      throw new BadRequestException('Missing required query parameter: token');
    }

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

    if (!shareableLink) {
      throw new NotFoundException('Shareable link not found');
    }

    // Check if link has expired
    const isExpired =
      shareableLink.expiresAt !== null && shareableLink.expiresAt < new Date();

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

  /**
   * GET /api/share/:token — OG preview HTML page with redirect
   * Returns HTML with OG meta tags, increments viewCount, tracks link tap event
   */
  async getOgPreview(token: string): Promise<string> {
    const shareableLink = await this.prisma.shareableLink.findUnique({
      where: { token },
    });

    if (!shareableLink) {
      throw new NotFoundException('Shareable link not found');
    }

    // Increment view count
    await this.prisma.shareableLink.update({
      where: { token },
      data: { viewCount: { increment: 1 } },
    });

    // Track link tap event
    await this.prisma.whatsAppAnalytics.create({
      data: {
        event: 'deep_link.tapped',
        metadata: JSON.stringify({
          shareToken: token,
          cardType: shareableLink.cardType,
        }),
      },
    }).catch(() => {
      // Don't fail the OG preview if analytics fails
    });

    // Build OG preview HTML
    const appBaseUrl = process.env.NEXT_PUBLIC_APP_URL ?? 'https://daxelo.app';
    const ogImageUrl = `${appBaseUrl}/api/share/og-image?token=${token}`;

    const html = `<!DOCTYPE html>
<html lang="en" prefix="og: https://ogp.me/ns#">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />

  <!-- OG Meta Tags -->
  <meta property="og:title" content="${this.escapeHtml(shareableLink.title)}" />
  <meta property="og:description" content="${this.escapeHtml(shareableLink.description)}" />
  <meta property="og:type" content="website" />
  <meta property="og:url" content="${appBaseUrl}/share/${token}" />
  <meta property="og:image" content="${ogImageUrl}" />

  <!-- Twitter Card Meta Tags -->
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${this.escapeHtml(shareableLink.title)}" />
  <meta name="twitter:description" content="${this.escapeHtml(shareableLink.description)}" />
  <meta name="twitter:image" content="${ogImageUrl}" />

  <title>${this.escapeHtml(shareableLink.title)} — DAXELO KINREL</title>

  <!-- Redirect to deep link after a short delay for OG crawlers -->
  <meta http-equiv="refresh" content="2;url=${this.escapeHtml(shareableLink.deepLinkUrl)}" />
</head>
<body>
  <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; background: #f9fafb; color: #111827;">
    <div style="text-align: center; padding: 2rem;">
      <h1 style="font-size: 1.5rem; margin-bottom: 0.5rem;">${this.escapeHtml(shareableLink.title)}</h1>
      <p style="color: #6b7280; margin-bottom: 1.5rem;">${this.escapeHtml(shareableLink.description)}</p>
      <p style="font-size: 0.875rem; color: #9ca3af;">Redirecting to DAXELO KINREL…</p>
      <a href="${this.escapeHtml(shareableLink.deepLinkUrl)}" style="display: inline-block; margin-top: 1rem; padding: 0.75rem 1.5rem; background: #4f46e5; color: #fff; border-radius: 0.5rem; text-decoration: none; font-weight: 600;">Open in App</a>
    </div>
  </div>
  <script>
    // Immediate redirect for browsers
    window.location.href = "${this.escapeHtml(shareableLink.deepLinkUrl)}";
  </script>
</body>
</html>`;

    return html;
  }

  private escapeHtml(str: string): string {
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }
}
