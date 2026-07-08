// server/src/pulse/pulse-push.listener.ts
//
// PulsePushListener — listens for 'pulse.brief.generated' events and sends
// an FCM push notification to the user.
//
// This is Pulse Phase 3: push notification delivery.
//
// Flow:
//   1. BriefGeneratorService.generateBriefForUser() emits 'pulse.brief.generated'
//      with { userId, familyId, briefDate, itemCount, itemTypes }
//   2. This listener catches the event (via @OnEvent)
//   3. Builds a localized push notification:
//        title: "🌅 Your family brief is ready"
//        body:  the brief summary (e.g. "2 people need you today, 1 birthday this week")
//   4. Calls FcmService.sendToUser(userId, { title, body, data })
//      — data includes deepLink: '/pulse/today' so tapping the notif opens the brief
//   5. On success, updates DailyBrief.deliveredAt = NOW()
//   6. If FCM is not initialized (no Firebase creds), skips silently — the brief
//      is still accessible via GET /pulse/today
//
// Why a listener (not inline in BriefGeneratorService)?
//   - Decoupling: the orchestrator shouldn't know about FCM
//   - Failure isolation: FCM errors don't break brief generation
//   - The orchestrator already emits the event for analytics — we just consume it
//
// Concurrency: events fire synchronously per user, but the listener is async.
// EventEmitter2 awaits handlers by default, so briefs are delivered in order.

import { Injectable, Logger } from '@nestjs/common';
import { OnEvent } from '@nestjs/event-emitter';
import { PrismaService } from '../prisma/prisma.service';
import { FcmService } from '../modules/notifications/fcm.service';

interface BriefGeneratedEvent {
  userId: string;
  familyId: string;
  briefDate: string; // 'YYYY-MM-DD'
  itemCount: number;
  itemTypes: string[];
}

// 8-language push notification titles + body templates.
// The body is the same summary the orchestrator generates, but we re-build it
// here from the itemTypes array because the event payload doesn't include the
// full summary text (keeping events lean).
const PUSH_TITLE: Record<string, string> = {
  en: '🌅 Your family brief is ready',
  hi: '🌅 आपका पारिवारिक संक्षेप तैयार है',
  ta: '🌅 உங்கள் குடும்ப சுருக்கம் தயார்',
  te: '🌅 మీ కుటుంబ సారాంశం సిద్ధంగా ఉంది',
  kn: '🌅 ನಿಮ್ಮ ಕುಟುಂಬದ ಸಾರಾಂಶ ಸಿದ್ಧವಾಗಿದೆ',
  mr: '🌅 तुमचा कौटुंबिक सारांश तयार आहे',
  gu: '🌅 તમારો પારિવારિક સારાંશ તૈયાર છે',
  bn: '🌅 আপনার পারিবারিক সারাংশ প্রস্তুত',
};

const EMPTY_BODY: Record<string, string> = {
  en: 'Nothing urgent today. Enjoy your family.',
  hi: 'आज कुछ जरूरी नहीं। परिवार का आनंद लें।',
  ta: 'இன்று அவசரம் இல்லை. குடும்பத்தை அனுபவிக்கவும்.',
  te: 'ఈరోజు అత్యవసరం లేదు. కుటుంబాన్ని ఆస్వాదించండి.',
  kn: 'ಇಂದು ಅತ್ಯವಶ್ಯಕವಿಲ್ಲ. ಕುಟುಂಬವನ್ನು ಆನಂದಿಸಿ.',
  mr: 'आज काही तातडीचे नाही. कुटुंबाचा आनंद घ्या.',
  gu: 'આજે કંઈ તાકીદ નથી. પરિવારનો આનંદ માણો.',
  bn: 'আজ জরুরি কিছু নেই। পরিবারের আনন্দ নিন।',
};

@Injectable()
export class PulsePushListener {
  private readonly logger = new Logger(PulsePushListener.name);

  constructor(
    private readonly fcm: FcmService,
    private readonly prisma: PrismaService,
  ) {}

  @OnEvent('pulse.brief.generated')
  async handleBriefGenerated(event: BriefGeneratedEvent): Promise<void> {
    const start = Date.now();
    try {
      // 1. Load the brief to get the localized greeting + summary + language
      const briefDate = new Date(event.briefDate + 'T00:00:00Z');
      const brief = await this.prisma.dailyBrief.findUnique({
        where: {
          userId_briefDate: {
            userId: event.userId,
            briefDate,
          },
        },
        select: {
          id: true,
          greeting: true,
          languageCode: true,
          content: true,
        },
      });

      if (!brief) {
        this.logger.warn(
          `PulsePush: brief not found for user ${event.userId} on ${event.briefDate} — skipping push`,
        );
        return;
      }

      // 2. Build the push body
      const lang = brief.languageCode || 'en';
      const title = PUSH_TITLE[lang] ?? PUSH_TITLE.en;

      // Extract summary from the content JSONB (set by the orchestrator)
      const contentObj =
        typeof brief.content === 'object' && brief.content !== null
          ? (brief.content as { summary?: string })
          : null;
      const summary = contentObj?.summary;
      const body =
        summary && summary.length > 0
          ? summary
          : (EMPTY_BODY[lang] ?? EMPTY_BODY.en);

      // 3. Send FCM push
      const sent = await this.fcm.sendToUser(event.userId, {
        title,
        body,
        data: {
          type: 'pulse_brief',
          briefId: brief.id,
          briefDate: event.briefDate,
          familyId: event.familyId,
          itemCount: String(event.itemCount),
          deepLink: '/pulse/today',
        },
      });

      // 4. Update DailyBrief.deliveredAt (only if push was sent)
      // We set deliveredAt regardless of FCM success — the brief WAS delivered
      // to the backend; the FCM push is a best-effort notification. If FCM
      // fails, the user can still see the brief via GET /pulse/today.
      // BUT: if FCM is not initialized (no Firebase creds), we DON'T set
      // deliveredAt — that field specifically means "push was sent".
      if (sent) {
        await this.prisma.dailyBrief.update({
          where: { id: brief.id },
          data: { deliveredAt: new Date() },
        });
        this.logger.debug(
          `PulsePush: delivered brief ${brief.id} to user ${event.userId} (${event.itemCount} items) in ${Date.now() - start}ms`,
        );
      } else {
        // FCM not initialized OR no tokens — log at debug level (this is normal
        // during local dev when Firebase creds aren't set)
        this.logger.debug(
          `PulsePush: FCM unavailable or no tokens for user ${event.userId} — brief ${brief.id} not pushed (still accessible via API)`,
        );
      }
    } catch (err) {
      // Never throw from an event handler — it would crash the EventEmitter
      this.logger.error(
        `PulsePush: failed to deliver brief to user ${event.userId}: ${err instanceof Error ? err.message : err}`,
        err instanceof Error ? err.stack : undefined,
      );
    }
  }
}
