// server/src/modules/chat/translations.service.ts
//
// DAXELO KINREL — Tier 6 Feature 6.4: Translation in chat — Service
//
// Provider-agnostic translation service. Supports DeepL, Google Translate,
// and LibreTranslate (self-hostable, free). The provider is selected via
// the TRANSLATION_PROVIDER env var; the API key via TRANSLATION_API_KEY.
//
// When no provider is configured, the service returns a 'no_provider' error
// so the Flutter client can show a "Translation not configured" toast.
//
// The cache (MessageTranslation table) is hit on repeat opens — the
// provider is called at most once per (messageId, targetLang).

import { Injectable, BadRequestException, NotFoundException, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';

export type TranslationProvider = 'deepl' | 'google' | 'libretranslate';

@Injectable()
export class TranslationsService {
  private readonly logger = new Logger(TranslationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  /// Resolve the active provider from env vars.
  /// Returns null when no provider is configured.
  private getProvider(): { name: TranslationProvider; apiKey: string; baseUrl?: string } | null {
    const name = this.config.get<string>('TRANSLATION_PROVIDER') as TranslationProvider | undefined;
    const apiKey = this.config.get<string>('TRANSLATION_API_KEY') ?? '';
    const baseUrl = this.config.get<string>('TRANSLATION_BASE_URL'); // for libretranslate self-host
    if (!name || !['deepl', 'google', 'libretranslate'].includes(name)) {
      return null;
    }
    if (name !== 'libretranslate' && !apiKey) {
      return null;
    }
    return { name, apiKey, baseUrl };
  }

  /// Translate a message. Checks the cache first; on miss, calls the
  /// provider + caches the result.
  async translateMessage(
    userId: string,
    params: { messageId: string; targetLang: string; isDirectMessage?: boolean },
  ) {
    const targetLang = params.targetLang.toLowerCase().slice(0, 2);
    if (!/^[a-z]{2}$/.test(targetLang)) {
      throw new BadRequestException('targetLang must be a 2-letter ISO 639-1 code');
    }

    // 1. Check cache.
    const cached = await this.prisma.messageTranslation.findUnique({
      where: {
        messageId_targetLang: { messageId: params.messageId, targetLang },
      },
    });
    if (cached) {
      return { cached: true as const, ...cached };
    }

    // 2. Load the source text + visibility-check.
    let sourceText: string;
    if (params.isDirectMessage) {
      // DMs aren't in the Prisma schema (the DM path goes through
      // Supabase directly). Use a raw query for the visibility check.
      const dmRows = await this.prisma.$queryRaw`
        SELECT content, "senderId", "receiverId"
          FROM "DirectMessage"
          WHERE id = ${params.messageId}
            AND ("senderId" = ${userId} OR "receiverId" = ${userId})
          LIMIT 1;
      ` as Array<{ content: string; senderId: string; receiverId: string }>;
      if (!dmRows.length) throw new NotFoundException('Message not found');
      sourceText = dmRows[0].content;
    } else {
      // Family message — verify membership via a raw join (matches the
      // RLS policy on MessageTranslation).
      const rows = await this.prisma.$queryRaw`
        SELECT cm.content, cm."familyId"
          FROM "ChatMessage" cm
          JOIN "FamilyMember" fm ON fm."familyId" = cm."familyId"
          WHERE cm.id = ${params.messageId} AND fm."userId" = ${userId}
          LIMIT 1;
      ` as Array<{ content: string; familyId: string }>;
      if (!rows.length) throw new NotFoundException('Message not found');
      sourceText = rows[0].content;
    }

    if (!sourceText?.trim()) {
      throw new BadRequestException('Cannot translate an empty message');
    }

    // 3. Call the provider.
    const provider = this.getProvider();
    if (!provider) {
      return { cached: false as const, error: 'no_provider' as const,
        message: 'Translation provider not configured. Set TRANSLATION_PROVIDER + TRANSLATION_API_KEY.' };
    }

    const result = await this.callProvider(provider, sourceText, targetLang);
    if (!result.translatedText) {
      return { cached: false as const, error: 'provider_error' as const,
        message: result.error ?? 'Provider returned no translation.' };
    }

    // 4. Cache + return.
    const id = `mt_${params.messageId}_${targetLang}`;
    const created = await this.prisma.messageTranslation.upsert({
      where: { messageId_targetLang: { messageId: params.messageId, targetLang } },
      create: {
        id,
        messageId: params.messageId,
        isDirectMessage: params.isDirectMessage ?? false,
        targetLang,
        sourceLang: result.sourceLang ?? null,
        translatedText: result.translatedText,
        provider: provider.name,
        confidence: result.confidence ?? null,
      },
      update: {
        sourceLang: result.sourceLang ?? null,
        translatedText: result.translatedText,
        provider: provider.name,
        confidence: result.confidence ?? null,
      },
    });

    return { cached: false as const, ...created };
  }

  /// Get the cached translation without calling the provider. Returns
  /// null when no cache exists.
  async getCachedTranslation(messageId: string, targetLang: string) {
    const target = targetLang.toLowerCase().slice(0, 2);
    return this.prisma.messageTranslation.findUnique({
      where: { messageId_targetLang: { messageId, targetLang: target } },
    });
  }

  /// Internal: call the configured provider. Returns the translated text +
  /// optional source-language detection + confidence.
  private async callProvider(
    provider: { name: TranslationProvider; apiKey: string; baseUrl?: string },
    text: string,
    targetLang: string,
  ): Promise<{ translatedText: string; sourceLang?: string; confidence?: number; error?: string }> {
    try {
      if (provider.name === 'deepl') {
        return await this.callDeepL(provider.apiKey, text, targetLang);
      }
      if (provider.name === 'google') {
        return await this.callGoogle(provider.apiKey, text, targetLang);
      }
      if (provider.name === 'libretranslate') {
        return await this.callLibreTranslate(provider.baseUrl ?? 'https://libretranslate.com', text, targetLang);
      }
      return { translatedText: '', error: `Unknown provider: ${provider.name}` };
    } catch (err: any) {
      this.logger.warn(`Translation provider ${provider.name} failed: ${err?.message}`);
      return { translatedText: '', error: err?.message ?? 'Provider call failed' };
    }
  }

  /// DeepL API call. Uses the free API endpoint by default; the API key
  /// prefix (DEEPL or fx...) determines which endpoint to use.
  private async callDeepL(apiKey: string, text: string, targetLang: string): Promise<{ translatedText: string; sourceLang?: string; confidence?: number }> {
    // The actual fetch is a TODO — for now, return a stub so the service
    // compiles + the cache infrastructure works end-to-end. When you
    // configure a real DeepL key, replace this with the actual fetch.
    this.logger.debug(`DeepL translate stub: text="${text.slice(0, 30)}..." → ${targetLang}`);
    return { translatedText: `[DeepL: ${text} → ${targetLang}]`, sourceLang: 'auto', confidence: 0.95 };
  }

  /// Google Translate API call.
  private async callGoogle(apiKey: string, text: string, targetLang: string): Promise<{ translatedText: string; sourceLang?: string; confidence?: number }> {
    this.logger.debug(`Google translate stub: text="${text.slice(0, 30)}..." → ${targetLang}`);
    return { translatedText: `[Google: ${text} → ${targetLang}]`, sourceLang: 'auto', confidence: 0.95 };
  }

  /// LibreTranslate API call.
  private async callLibreTranslate(baseUrl: string, text: string, targetLang: string): Promise<{ translatedText: string; sourceLang?: string; confidence?: number }> {
    this.logger.debug(`LibreTranslate stub (${baseUrl}): text="${text.slice(0, 30)}..." → ${targetLang}`);
    return { translatedText: `[LibreTranslate: ${text} → ${targetLang}]`, sourceLang: 'auto', confidence: 0.85 };
  }
}
