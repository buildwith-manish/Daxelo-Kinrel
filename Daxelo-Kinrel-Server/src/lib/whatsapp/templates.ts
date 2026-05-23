// DAXELO KINREL — WhatsApp Template Catalog & Sending Functions
// Pack 04: WhatsApp Platform
// Pre-approved WhatsApp Business API message templates with opt-in checks and fallbacks

import { whatsappClient } from './client'
import { db } from '@/lib/db'

// ── Template Component Types ────────────────────────────────────────

interface TemplateComponent {
  type: 'HEADER' | 'BODY' | 'FOOTER' | 'BUTTON'
  format?: 'TEXT' | 'IMAGE' | 'DOCUMENT' | 'VIDEO'
  text?: string
  buttonType?: 'QUICK_REPLY' | 'URL'
  url?: string
}

interface TemplateLanguage {
  code: string
  components: TemplateComponent[]
}

interface TemplateDefinition {
  name: string
  category: 'AUTHENTICATION' | 'UTILITY' | 'MARKETING' | 'SERVICE'
  languages: TemplateLanguage[]
}

// ── Template Catalog ────────────────────────────────────────────────

export const TEMPLATE_CATALOG: Record<string, TemplateDefinition> = {
  verification_code: {
    name: 'verification_code',
    category: 'AUTHENTICATION',
    languages: [
      {
        code: 'en',
        components: [
          {
            type: 'BODY',
            text: 'Your Daxelo Kinrel verification code is {{1}}. Valid for {{2}} minutes. Do not share this code.',
          },
          {
            type: 'FOOTER',
            text: 'Daxelo Kinrel — Family Relationship Intelligence',
          },
          {
            type: 'BUTTON',
            buttonType: 'URL',
            text: 'Copy Code',
            url: '{{1}}',
          },
        ],
      },
      {
        code: 'hi',
        components: [
          {
            type: 'BODY',
            text: 'आपका दक्षेलो किनरेल सत्यापन कोड {{1}} है। {{2}} मिनट तक मान्य। इस कोड को साझा न करें।',
          },
        ],
      },
    ],
  },

  birthday_reminder: {
    name: 'birthday_reminder',
    category: 'UTILITY',
    languages: [
      {
        code: 'en',
        components: [
          {
            type: 'HEADER',
            format: 'TEXT',
            text: '🎂 Birthday Reminder',
          },
          {
            type: 'BODY',
            text: "It's {{1}}'s birthday today! 🎉\n\nSend them your wishes or share a family memory.",
          },
          {
            type: 'FOOTER',
            text: 'Daxelo Kinrel',
          },
          {
            type: 'BUTTON',
            buttonType: 'QUICK_REPLY',
            text: 'Send Wish',
          },
          {
            type: 'BUTTON',
            buttonType: 'URL',
            text: 'View Profile',
            url: 'https://daxelokinrel.com/person/{{2}}',
          },
        ],
      },
      {
        code: 'hi',
        components: [
          {
            type: 'BODY',
            text: 'आज {{1}} का जन्मदिन है! 🎉\n\nउन्हें शुभकामनाएं भेजें या पारिवारिक याद साझा करें।',
          },
        ],
      },
    ],
  },

  family_invite: {
    name: 'family_invite',
    category: 'UTILITY',
    languages: [
      {
        code: 'en',
        components: [
          {
            type: 'HEADER',
            format: 'TEXT',
            text: '👨‍👩‍👧‍👦 Family Invitation',
          },
          {
            type: 'BODY',
            text: '{{1}} has invited you to join their family tree on Daxelo Kinrel!\n\nJoin to explore your family relationships, share memories, and stay connected.',
          },
          {
            type: 'FOOTER',
            text: 'Daxelo Kinrel — Know your family',
          },
          {
            type: 'BUTTON',
            buttonType: 'URL',
            text: 'Join Family',
            url: 'https://daxelokinrel.com/invite/{{2}}',
          },
        ],
      },
      {
        code: 'hi',
        components: [
          {
            type: 'BODY',
            text: '{{1}} ने आपको दक्षेलो किनरेल पर अपने पारिवारिक वृक्ष में शामिल होने के लिए आमंत्रित किया है!\n\nअपने पारिवारिक रिश्तों को जानने, यादें साझा करने और जुड़े रहने के लिए शामिल हों।',
          },
        ],
      },
    ],
  },

  new_match: {
    name: 'new_match',
    category: 'UTILITY',
    languages: [
      {
        code: 'en',
        components: [
          {
            type: 'BODY',
            text: '💕 New match found!\n\n{{1}} — {{2}}% compatible\n{{3}} | {{4}}\n\nView their profile in the app.',
          },
          {
            type: 'BUTTON',
            buttonType: 'URL',
            text: 'View Match',
            url: 'https://daxelokinrel.com/matrimonial/profile/{{5}}',
          },
        ],
      },
      {
        code: 'hi',
        components: [
          {
            type: 'BODY',
            text: '💕 नया मैच मिला!\n\n{{1}} — {{2}}% सुसंगत\n{{3}} | {{4}}\n\nऐप में प्रोफ़ाइल देखें।',
          },
        ],
      },
    ],
  },

  interest_received: {
    name: 'interest_received',
    category: 'UTILITY',
    languages: [
      {
        code: 'en',
        components: [
          {
            type: 'BODY',
            text: '💌 Someone is interested in your profile!\n\n{{1}} has expressed interest. Check their profile and respond.',
          },
          {
            type: 'BUTTON',
            buttonType: 'URL',
            text: 'View Profile',
            url: 'https://daxelokinrel.com/matrimonial/profile/{{2}}',
          },
          {
            type: 'BUTTON',
            buttonType: 'QUICK_REPLY',
            text: 'Not Interested',
          },
        ],
      },
      {
        code: 'hi',
        components: [
          {
            type: 'BODY',
            text: '💌 किसी ने आपकी प्रोफ़ाइल में रुचि दिखाई!\n\n{{1}} ने रुचि व्यक्त की है। उनकी प्रोफ़ाइल देखें और जवाब दें।',
          },
        ],
      },
    ],
  },

  subscription_reminder: {
    name: 'subscription_reminder',
    category: 'UTILITY',
    languages: [
      {
        code: 'en',
        components: [
          {
            type: 'BODY',
            text: 'Your Daxelo Kinrel {{1}} subscription expires in {{2}} days.\n\nRenew to keep access to premium features like unlimited interests and priority matching.',
          },
          {
            type: 'BUTTON',
            buttonType: 'URL',
            text: 'Renew Now',
            url: 'https://daxelokinrel.com/subscription',
          },
        ],
      },
      {
        code: 'hi',
        components: [
          {
            type: 'BODY',
            text: 'आपकी दक्षेलो किनरेल {{1}} सदस्यता {{2}} दिनों में समाप्त होगी।\n\nअसीमित रुचि और प्राथमिकता मिलान जैसी प्रीमियम सुविधाओं तक पहुंच बनाए रखने के लिए नवीनीकरण करें।',
          },
        ],
      },
    ],
  },

  welcome_message: {
    name: 'welcome_message',
    category: 'SERVICE',
    languages: [
      {
        code: 'en',
        components: [
          {
            type: 'BODY',
            text: "👋 Welcome to Daxelo Kinrel Bot!\n\nI can help you with:\n• Find family members\n• Birthday reminders\n• Family statistics\n• Matrimonial matches\n\nType 'help' for all commands.",
          },
        ],
      },
      {
        code: 'hi',
        components: [
          {
            type: 'BODY',
            text: "👋 दक्षेलो किनरेल बॉट में आपका स्वागत है!\n\nमैं आपकी मदद कर सकता हूं:\n• परिवार के सदस्य खोजें\n• जन्मदिन रिमाइंडर\n• परिवार के आँकड़े\n• विवाह मिलान\n\nसभी कमांड के लिए 'मदद' टाइप करें।",
          },
        ],
      },
    ],
  },
}

// ── Opt-in Check ────────────────────────────────────────────────────

async function checkWhatsAppOptIn(
  phone: string,
  templateType: string,
): Promise<boolean> {
  try {
    const optIn = await db.whatsAppOptIn.findUnique({
      where: {
        phone_templateType: { phone, templateType },
      },
    })
    return optIn?.optedIn ?? false
  } catch (error) {
    console.error(
      `[Templates] Error checking opt-in for ${phone}/${templateType}:`,
      error,
    )
    // Fail closed — if we can't verify opt-in, don't send
    return false
  }
}

// ── Record Opt-In ───────────────────────────────────────────────────

export async function recordOptIn(
  phone: string,
  templateType: string,
): Promise<void> {
  await db.whatsAppOptIn.upsert({
    where: {
      phone_templateType: { phone, templateType },
    },
    create: {
      phone,
      templateType,
      optedIn: true,
      optedInAt: new Date(),
    },
    update: {
      optedIn: true,
      optedInAt: new Date(),
    },
  })
}

// ── Record Opt-Out ──────────────────────────────────────────────────

export async function recordOptOut(
  phone: string,
  templateType: string,
): Promise<void> {
  await db.whatsAppOptIn.upsert({
    where: {
      phone_templateType: { phone, templateType },
    },
    create: {
      phone,
      templateType,
      optedIn: false,
    },
    update: {
      optedIn: false,
      optedInAt: null,
    },
  })
}

// ── Send with Template Fallback ─────────────────────────────────────

async function sendWithFallback(
  phone: string,
  templateName: string,
  language: string,
  parameters: string[],
  fallbackMessage: string,
): Promise<void> {
  try {
    // Check if the template is approved in our database
    const templateRecord = await db.whatsAppTemplate.findUnique({
      where: { name: templateName },
    })

    if (templateRecord?.status === 'approved') {
      await whatsappClient.sendTemplateMessage(
        phone,
        templateName,
        language,
        parameters,
      )
      return
    }

    // Template not approved — fall back to free-form message
    console.warn(
      `[Templates] Template "${templateName}" not approved (status: ${templateRecord?.status ?? 'not_found'}), using fallback for ${phone}`,
    )
    await whatsappClient.sendTextMessage(phone, fallbackMessage)
  } catch (error: unknown) {
    const errorMessage =
      error instanceof Error ? error.message : String(error)

    if (errorMessage.includes('template') || errorMessage.includes('not found')) {
      // Template issue — fall back to free-form message
      console.warn(
        `[Templates] Template "${templateName}" unavailable, using fallback for ${phone}: ${errorMessage}`,
      )
      try {
        await whatsappClient.sendTextMessage(phone, fallbackMessage)
      } catch (fallbackError) {
        console.error(
          `[Templates] Fallback message also failed for ${phone}:`,
          fallbackError,
        )
      }
    } else {
      throw error
    }
  }
}

// ── Send Birthday Reminder ──────────────────────────────────────────

export async function sendBirthdayReminder(
  phone: string,
  personName: string,
  personId: string,
  language: string = 'en',
): Promise<void> {
  // Check opt-in before sending
  const optedIn = await checkWhatsAppOptIn(phone, 'birthday_reminder')
  if (!optedIn) {
    console.log(
      `[Templates] Skipping birthday reminder for ${phone} — not opted in`,
    )
    return
  }

  const isHindi = language === 'hi'
  const fallbackMessage = isHindi
    ? `🎂 आज ${personName} का जन्मदिन है! 🎉\n\nउन्हें शुभकामनाएं भेजें या पारिवारिक याद साझा करें।`
    : `🎂 It's ${personName}'s birthday today! 🎉\n\nSend them your wishes or share a family memory.`

  await sendWithFallback(
    phone,
    'birthday_reminder',
    language,
    [personName, personId],
    fallbackMessage,
  )
}

// ── Send Family Invite ──────────────────────────────────────────────

export async function sendFamilyInvite(
  phone: string,
  inviterName: string,
  inviteToken: string,
  familyName: string,
  language: string = 'en',
): Promise<void> {
  // Family invites are user-initiated — opt-in not strictly required,
  // but we still check general WhatsApp consent
  const consent = await db.whatsAppConsent.findFirst({
    where: { phone },
  })

  // If the user has explicitly opted out, don't send
  if (consent && !consent.optedIn) {
    console.log(
      `[Templates] Skipping family invite for ${phone} — user opted out`,
    )
    return
  }

  const isHindi = language === 'hi'
  const deepLink = `https://daxelokinrel.com/invite/${inviteToken}`
  const fallbackMessage = isHindi
    ? `👨‍👩‍👧‍👦 ${inviterName} ने आपको *${familyName}* परिवार में शामिल होने के लिए आमंत्रित किया है!\n\nशामिल होने के लिए टैप करें: ${deepLink}`
    : `👨‍👩‍👧‍👦 ${inviterName} has invited you to join the *${familyName}* family on Daxelo Kinrel!\n\nTap to join: ${deepLink}`

  await sendWithFallback(
    phone,
    'family_invite',
    language,
    [inviterName, inviteToken],
    fallbackMessage,
  )
}

// ── Send New Match Notification ─────────────────────────────────────

export async function sendNewMatchNotification(
  phone: string,
  matchName: string,
  compatibilityScore: number,
  education: string,
  city: string,
  profileId: string,
  language: string = 'en',
): Promise<void> {
  // Check opt-in before sending
  const optedIn = await checkWhatsAppOptIn(phone, 'new_match')
  if (!optedIn) {
    console.log(
      `[Templates] Skipping new match notification for ${phone} — not opted in`,
    )
    return
  }

  const isHindi = language === 'hi'
  const fallbackMessage = isHindi
    ? `💕 नया मैच मिला!\n\n${matchName} — ${compatibilityScore}% सुसंगत\n${education} | ${city}\n\nऐप में प्रोफ़ाइल देखें: https://daxelokinrel.com/matrimonial/profile/${profileId}`
    : `💕 New match found!\n\n${matchName} — ${compatibilityScore}% compatible\n${education} | ${city}\n\nView their profile: https://daxelokinrel.com/matrimonial/profile/${profileId}`

  await sendWithFallback(
    phone,
    'new_match',
    language,
    [
      matchName,
      compatibilityScore.toString(),
      education,
      city,
      profileId,
    ],
    fallbackMessage,
  )
}

// ── Send Verification Code ──────────────────────────────────────────

export async function sendVerificationCode(
  phone: string,
  code: string,
  validityMinutes: number = 10,
  language: string = 'en',
): Promise<void> {
  // Authentication messages don't require opt-in per WhatsApp policy
  const isHindi = language === 'hi'
  const fallbackMessage = isHindi
    ? `आपका दक्षेलो किनरेल सत्यापन कोड ${code} है। ${validityMinutes} मिनट तक मान्य। इस कोड को साझा न करें।`
    : `Your Daxelo Kinrel verification code is ${code}. Valid for ${validityMinutes} minutes. Do not share this code.`

  await sendWithFallback(
    phone,
    'verification_code',
    language,
    [code, validityMinutes.toString()],
    fallbackMessage,
  )
}

// ── Send Interest Received ──────────────────────────────────────────

export async function sendInterestReceived(
  phone: string,
  senderName: string,
  senderProfileId: string,
  language: string = 'en',
): Promise<void> {
  // Check opt-in before sending
  const optedIn = await checkWhatsAppOptIn(phone, 'interest_received')
  if (!optedIn) {
    console.log(
      `[Templates] Skipping interest received notification for ${phone} — not opted in`,
    )
    return
  }

  const isHindi = language === 'hi'
  const fallbackMessage = isHindi
    ? `💌 किसी ने आपकी प्रोफ़ाइल में रुचि दिखाई!\n\n${senderName} ने रुचि व्यक्त की है। ऐप में प्रोफ़ाइल देखें: https://daxelokinrel.com/matrimonial/profile/${senderProfileId}`
    : `💌 Someone is interested in your profile!\n\n${senderName} has expressed interest. View their profile: https://daxelokinrel.com/matrimonial/profile/${senderProfileId}`

  await sendWithFallback(
    phone,
    'interest_received',
    language,
    [senderName, senderProfileId],
    fallbackMessage,
  )
}

// ── Send Subscription Reminder ──────────────────────────────────────

export async function sendSubscriptionReminder(
  phone: string,
  planName: string,
  daysRemaining: number,
  language: string = 'en',
): Promise<void> {
  // Check opt-in before sending
  const optedIn = await checkWhatsAppOptIn(phone, 'subscription_reminder')
  if (!optedIn) {
    console.log(
      `[Templates] Skipping subscription reminder for ${phone} — not opted in`,
    )
    return
  }

  const isHindi = language === 'hi'
  const fallbackMessage = isHindi
    ? `आपकी दक्षेलो किनरेल ${planName} सदस्यता ${daysRemaining} दिनों में समाप्त होगी।\n\nनवीनीकरण करें: https://daxelokinrel.com/subscription`
    : `Your Daxelo Kinrel ${planName} subscription expires in ${daysRemaining} days.\n\nRenew now: https://daxelokinrel.com/subscription`

  await sendWithFallback(
    phone,
    'subscription_reminder',
    language,
    [planName, daysRemaining.toString()],
    fallbackMessage,
  )
}

// ── Send Welcome Message ────────────────────────────────────────────

export async function sendWelcomeMessage(
  phone: string,
  language: string = 'en',
): Promise<void> {
  // Welcome messages are service messages (user-initiated) — opt-in not required
  const isHindi = language === 'hi'
  const fallbackMessage = isHindi
    ? "👋 दक्षेलो किनरेल बॉट में आपका स्वागत है!\n\nमैं आपकी मदद कर सकता हूं:\n• परिवार के सदस्य खोजें\n• जन्मदिन रिमाइंडर\n• परिवार के आँकड़े\n• विवाह मिलान\n\nसभी कमांड के लिए 'मदद' टाइप करें।"
    : "👋 Welcome to Daxelo Kinrel Bot!\n\nI can help you with:\n• Find family members\n• Birthday reminders\n• Family statistics\n• Matrimonial matches\n\nType 'help' for all commands."

  await sendWithFallback(
    phone,
    'welcome_message',
    language,
    [],
    fallbackMessage,
  )
}

// ── Sync Template Catalog to Database ───────────────────────────────

export async function syncTemplateCatalog(): Promise<void> {
  for (const [key, template] of Object.entries(TEMPLATE_CATALOG)) {
    const languageCodes = template.languages.map((l) => l.code)

    await db.whatsAppTemplate.upsert({
      where: { name: template.name },
      create: {
        name: template.name,
        category: template.category,
        languages: JSON.stringify(languageCodes),
        components: JSON.stringify(template.languages),
        status: 'pending',
      },
      update: {
        category: template.category,
        languages: JSON.stringify(languageCodes),
        components: JSON.stringify(template.languages),
      },
    })

    console.log(
      `[Templates] Synced template: ${template.name} (${key}) — ${languageCodes.join(', ')}`,
    )
  }

  console.log('[Templates] Template catalog sync complete')
}

// ── Get Template Status ─────────────────────────────────────────────

export async function getTemplateStatus(): Promise<
  Array<{
    name: string
    category: string
    status: string
    languages: string[]
    whatsappId: string | null
    rejectionReason: string | null
  }>
> {
  const templates = await db.whatsAppTemplate.findMany({
    orderBy: { category: 'asc' },
  })

  return templates.map((t) => ({
    name: t.name,
    category: t.category,
    status: t.status,
    languages: JSON.parse(t.languages) as string[],
    whatsappId: t.whatsappId,
    rejectionReason: t.rejectionReason,
  }))
}
