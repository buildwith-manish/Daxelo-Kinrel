// DAXELO KINREL — WhatsApp Bot Command Router
// Pack 04: WhatsApp Platform
// Multi-language command parsing and full handler implementations

import { whatsappClient, WhatsAppMessage } from './client'
import { sessionManager, SessionState, BotSession } from './session-manager'
import { db } from '@/lib/db'

// ── Supported Languages ─────────────────────────────────────────────

const SUPPORTED_LANGUAGES = ['en', 'hi', 'te', 'ta'] as const
type SupportedLanguage = (typeof SUPPORTED_LANGUAGES)[number]

// ── Parsed Command ──────────────────────────────────────────────────

interface ParsedCommand {
  type: string
  args: string
}

// ── Multi-Language Command Parser ───────────────────────────────────

const COMMAND_PATTERNS: Array<{ patterns: RegExp[]; type: string }> = [
  {
    patterns: [
      /^(who is|kaun hai|कौन है|ఎవరు|யார்)\s+/i,
    ],
    type: 'who',
  },
  {
    patterns: [
      /^(relation|rishta|रिश्ता|సంబంధం|உறவு)\s*/i,
    ],
    type: 'relation',
  },
  {
    patterns: [
      /^(birthday|janmdin|जन्मदिन|పుట్టినరోజు|பிறந்தநாள்)/i,
    ],
    type: 'birthday',
  },
  {
    patterns: [
      /^(count|kitne|कितने|ఎంతమంది|எத்தனை)/i,
    ],
    type: 'count',
  },
  {
    patterns: [
      /^(add|jodo|जोड़ो|చేర్చు|சேர்)\s*/i,
    ],
    type: 'add',
  },
  {
    patterns: [
      /^(invite|bulao|बुलाओ|ఆహ్వానించు|அழை)\s*/i,
    ],
    type: 'invite',
  },
  {
    patterns: [
      /^(matches|milan|मिलन|మ్యాచ్‌లు|பொருத்தங்கள்)/i,
    ],
    type: 'matches',
  },
  {
    patterns: [
      /^(help|madad|मदद|సహాయం|உதவி)/i,
    ],
    type: 'help',
  },
  {
    patterns: [
      /^(language|bhasha|भाषा|భాష|மொழி)\s*/i,
    ],
    type: 'language',
  },
]

function parseCommand(text: string): ParsedCommand {
  const lower = text.toLowerCase().trim()

  for (const cmd of COMMAND_PATTERNS) {
    for (const pattern of cmd.patterns) {
      if (pattern.test(lower)) {
        const args = text.replace(pattern, '').trim()
        return { type: cmd.type, args }
      }
    }
  }

  return { type: 'unknown', args: text }
}

// ── Phone Normalization ─────────────────────────────────────────────

function normalizePhone(phone: string): string {
  return phone.replace(/^\+91/, '').replace(/^\+/, '')
}

// ── Age Calculation ─────────────────────────────────────────────────

function getAge(dob: Date): number {
  const today = new Date()
  let age = today.getFullYear() - dob.getFullYear()
  const m = today.getMonth() - dob.getMonth()
  if (m < 0 || (m === 0 && today.getDate() < dob.getDate())) age--
  return age
}

// ── Get User Language ───────────────────────────────────────────────

function getUserLanguage(user: { preferredLanguage?: string | null } | null): SupportedLanguage {
  const lang = user?.preferredLanguage ?? 'en'
  if (SUPPORTED_LANGUAGES.includes(lang as SupportedLanguage)) {
    return lang as SupportedLanguage
  }
  return 'en'
}

function isHindi(user: { preferredLanguage?: string | null } | null): boolean {
  return getUserLanguage(user) === 'hi'
}

// ── Main Route Command ──────────────────────────────────────────────

export async function routeCommand(msg: WhatsAppMessage): Promise<void> {
  const phone = msg.from
  const text = msg.text?.body?.trim() ?? ''
  const buttonReply = (msg.interactive?.button_reply as { id: string } | undefined)?.id
  const listReply = (msg.interactive?.list_reply as { id: string } | undefined)?.id

  // Look up user by phone
  const normalizedPhone = normalizePhone(phone)
  const user = await db.user.findFirst({
    where: { phone: { contains: normalizedPhone } },
  })

  // Get or create session
  const session = await sessionManager.getOrCreate(phone)

  // If user is in a multi-step flow, route to flow handler
  if (session.state !== SessionState.IDLE) {
    await handleFlowState(phone, session, text, buttonReply, user)
    return
  }

  // Handle button/list replies first (when in IDLE state)
  if (buttonReply) {
    await handleButtonReply(phone, buttonReply, user)
    return
  }

  if (listReply) {
    await handleListReply(phone, listReply, user)
    return
  }

  // Parse text command
  const command = parseCommand(text)

  switch (command.type) {
    case 'who':
      await handleWhoCommand(phone, user, command.args)
      break
    case 'relation':
      await handleRelationCommand(phone, user, command.args)
      break
    case 'birthday':
      await handleBirthdayCommand(phone, user)
      break
    case 'count':
      await handleCountCommand(phone, user)
      break
    case 'add':
      await handleAddCommand(phone, user, command.args)
      break
    case 'invite':
      await handleInviteCommand(phone, user, command.args)
      break
    case 'matches':
      await handleMatchesCommand(phone, user)
      break
    case 'help':
      await handleHelpCommand(phone, user)
      break
    case 'language':
      await handleLanguageCommand(phone, user, command.args)
      break
    case 'unknown':
    default:
      await handleUnknownCommand(phone, user)
  }
}

// ── Help Command ────────────────────────────────────────────────────

export async function handleHelpCommand(
  phone: string,
  user: { id?: string; preferredLanguage?: string | null } | null,
): Promise<void> {
  const hi = isHindi(user)

  await whatsappClient.sendListMessage(
    phone,
    hi ? '🤖 दक्षेलो किनरेल बॉट' : '🤖 Daxelo Kinrel Bot',
    hi
      ? 'मैं आपके परिवार के बारे में जानकारी दे सकता हूं'
      : 'I can help you with your family information',
    [
      {
        title: hi ? 'जानकारी' : 'Information',
        rows: [
          {
            id: 'cmd_who',
            title: hi ? 'कौन है [नाम]' : 'Who is [name]',
            description: 'Find a family member',
          },
          {
            id: 'cmd_birthday',
            title: hi ? 'जन्मदिन' : 'Birthday',
            description: hi ? 'आज के जन्मदिन' : "Today's birthdays",
          },
          {
            id: 'cmd_count',
            title: hi ? 'कितने सदस्य' : 'Family count',
            description: hi ? 'परिवार के सदस्य' : 'Family member stats',
          },
          {
            id: 'cmd_relation',
            title: hi ? 'रिश्ता' : 'Relation',
            description: hi ? 'रिश्ते की जानकारी' : 'Relationship info',
          },
        ],
      },
      {
        title: hi ? 'कार्रवाई' : 'Actions',
        rows: [
          {
            id: 'cmd_add',
            title: hi ? 'सदस्य जोड़ें' : 'Add member',
            description: hi ? 'नया सदस्य जोड़ें' : 'Add a family member',
          },
          {
            id: 'cmd_invite',
            title: hi ? 'परिवार को आमंत्रित करें' : 'Invite family',
            description: hi ? 'परिवार को ऐप पर बुलाएं' : 'Invite family to the app',
          },
        ],
      },
      {
        title: hi ? 'मैचिंग' : 'Matching',
        rows: [
          {
            id: 'cmd_matches',
            title: hi ? 'मैच देखें' : 'View matches',
            description: hi ? 'विवाह मैच' : 'Matrimonial matches',
          },
        ],
      },
      {
        title: hi ? 'सेटिंग्स' : 'Settings',
        rows: [
          {
            id: 'cmd_language',
            title: hi ? 'भाषा बदलें' : 'Change language',
            description: hi ? 'भाषा चुनें' : 'Select your language',
          },
        ],
      },
    ],
    hi ? 'विकल्प चुनें' : 'Choose option',
  )
}

// ── Unknown Command ─────────────────────────────────────────────────

export async function handleUnknownCommand(
  phone: string,
  user: { id?: string; preferredLanguage?: string | null } | null,
): Promise<void> {
  const hi = isHindi(user)

  await whatsappClient.sendInteractiveMessage(
    phone,
    hi ? '🤔 समझ नहीं आया' : "🤔 I didn't understand that",
    hi
      ? 'यहां कुछ चीजें हैं जो मैं कर सकता हूं:'
      : 'Here are some things I can help with:',
    [
      { id: 'cmd_help', title: hi ? 'मदद' : 'Help' },
      { id: 'cmd_birthday', title: hi ? 'जन्मदिन' : 'Birthdays' },
      { id: 'cmd_count', title: hi ? 'सदस्य गिनती' : 'Family count' },
    ],
  )
}

// ── Who Is Command ──────────────────────────────────────────────────

export async function handleWhoCommand(
  phone: string,
  user: { id?: string; preferredLanguage?: string | null } | null,
  name: string,
): Promise<void> {
  const hi = isHindi(user)

  if (!user?.id) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? '👋 मुझे यह नंबर पहचान नहीं आया। कृपया पहले daxelokinrel.com पर साइन अप करें!'
        : "👋 I don't recognize this number. Please sign up at daxelokinrel.com first!",
    )
    return
  }

  if (!name) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? 'आप किसके बारे में जानना चाहते हैं? उदाहरण: "कौन है प्रिया" या "who is Priya"'
        : "Who do you want to know about? Try: 'who is Priya' or 'कौन है प्रिया'",
    )
    return
  }

  const families = await db.family.findMany({
    where: { members: { some: { userId: user.id } } },
    include: {
      persons: {
        where: { name: { contains: name } },
        take: 5,
      },
    },
  })

  const persons = families.flatMap((f) =>
    f.persons.map((p) => ({ ...p, familyName: f.name })),
  )

  if (persons.length === 0) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? `मुझे आपके परिवार वृक्ष में "${name}" नाम का कोई व्यक्ति नहीं मिला।`
        : `I couldn't find anyone named "${name}" in your family tree.`,
    )
    return
  }

  if (persons.length > 1) {
    const names = persons.map((p) => `• ${p.name} (${p.familyName})`).join('\n')
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? `${persons.length} लोग मिले:\n${names}\n\nकौन सा? पूरा नाम बताएं।`
        : `Found ${persons.length} people:\n${names}\n\nWhich one? Share the full name.`,
    )
    // Set session to selecting_person state
    await sessionManager.setState(phone, SessionState.SELECTING_PERSON, {
      matchingPersons: persons.map((p) => ({ id: p.id, name: p.name })),
    })
    return
  }

  const person = persons[0]
  const age = person.dateOfBirth ? getAge(person.dateOfBirth) : null

  let reply = `📋 *${person.name}*\n`
  if (person.relationship) reply += `${hi ? 'रिश्ता' : 'Relationship'}: ${person.relationship}\n`
  if (age !== null) reply += `${hi ? 'उम्र' : 'Age'}: ${age}\n`
  if (person.gotra) reply += `Gotra: ${person.gotra}\n`
  if (person.occupation) reply += `${hi ? 'व्यवसाय' : 'Occupation'}: ${person.occupation}\n`
  if (person.city) reply += `${hi ? 'शहर' : 'City'}: ${person.city}\n`
  reply += `${hi ? 'परिवार' : 'Family'}: ${person.familyName}`

  await whatsappClient.sendTextMessage(phone, reply)
}

// ── Relation Command ────────────────────────────────────────────────

export async function handleRelationCommand(
  phone: string,
  user: { id?: string; preferredLanguage?: string | null } | null,
  args: string,
): Promise<void> {
  const hi = isHindi(user)

  if (!user?.id) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? '👋 कृपया पहले daxelokinrel.com पर साइन अप करें!'
        : '👋 Please sign up at daxelokinrel.com first!',
    )
    return
  }

  if (!args) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? 'रिश्ता जानने के लिए नाम बताएं। उदाहरण: "relation Priya" या "रिश्ता प्रिया"'
        : 'Share a name to find their relationship. Example: "relation Priya" or "रिश्ता प्रिया"',
    )
    return
  }

  // Look up the person by name across all user's families
  const families = await db.family.findMany({
    where: { members: { some: { userId: user.id } } },
    include: {
      persons: {
        where: { name: { contains: args } },
        take: 5,
      },
    },
  })

  const persons = families.flatMap((f) =>
    f.persons.map((p) => ({ ...p, familyName: f.name })),
  )

  if (persons.length === 0) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? `मुझे "${args}" नाम का कोई व्यक्ति नहीं मिला।`
        : `I couldn't find anyone named "${args}" in your family tree.`,
    )
    return
  }

  // Build a response showing relationships
  const lines = persons.map((p) => {
    const rel = p.relationship ?? (hi ? 'अज्ञात' : 'Unknown')
    return `• ${p.name} — ${rel} (${p.familyName})`
  })

  const response = hi
    ? `🔗 *रिश्ते की जानकारी*\n\n${lines.join('\n')}`
    : `🔗 *Relationship Information*\n\n${lines.join('\n')}`

  await whatsappClient.sendTextMessage(phone, response)
}

// ── Birthday Command ────────────────────────────────────────────────

export async function handleBirthdayCommand(
  phone: string,
  user: { id?: string; preferredLanguage?: string | null } | null,
): Promise<void> {
  const hi = isHindi(user)

  if (!user?.id) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? '👋 कृपया पहले daxelokinrel.com पर साइन अप करें!'
        : '👋 Please sign up at daxelokinrel.com first!',
    )
    return
  }

  const families = await db.family.findMany({
    where: { members: { some: { userId: user.id } } },
    include: {
      persons: {
        where: { dateOfBirth: { not: null } },
      },
    },
  })

  const today = new Date()
  const birthdays = families
    .flatMap((f) =>
      f.persons.map((p) => ({ ...p, familyName: f.name })),
    )
    .filter((p) => {
      if (!p.dateOfBirth) return false
      const dob = new Date(p.dateOfBirth)
      return dob.getMonth() === today.getMonth() && dob.getDate() === today.getDate()
    })

  // Also get upcoming birthdays in the next 7 days
  const upcomingBirthdays: Array<{
    name: string
    familyName: string
    daysAway: number
  }> = []

  for (const f of families) {
    for (const p of f.persons) {
      if (!p.dateOfBirth) continue
      const dob = new Date(p.dateOfBirth)
      const thisYearBday = new Date(
        today.getFullYear(),
        dob.getMonth(),
        dob.getDate(),
      )
      if (thisYearBday < today) {
        thisYearBday.setFullYear(today.getFullYear() + 1)
      }
      const diffDays = Math.ceil(
        (thisYearBday.getTime() - today.getTime()) / (1000 * 60 * 60 * 24),
      )
      if (diffDays > 0 && diffDays <= 7) {
        upcomingBirthdays.push({
          name: p.name,
          familyName: f.name,
          daysAway: diffDays,
        })
      }
    }
  }

  if (birthdays.length === 0 && upcomingBirthdays.length === 0) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? '🎂 आज कोई जन्मदिन नहीं है! इस हफ्ते भी कोई जन्मदिन नहीं है। ऐप में आने वाले जन्मदिन देखें।'
        : "🎂 No birthdays today! No birthdays this week either. Check the app for upcoming birthdays.",
    )
    return
  }

  let response = ''

  if (birthdays.length > 0) {
    const todayList = birthdays
      .map((p) => `• ${p.name} (${p.familyName})`)
      .join('\n')
    response += hi
      ? `🎂 *आज जन्मदिन है!*\n${todayList}\n\nशुभकामनाएं भेजें! 🎉\n\n`
      : `🎂 *Birthday today!*\n${todayList}\n\nSend them a wish! 🎉\n\n`
  }

  if (upcomingBirthdays.length > 0) {
    const upcomingList = upcomingBirthdays
      .map((b) => `• ${b.name} — ${b.daysAway === 1 ? (hi ? 'कल' : 'tomorrow') : `${b.daysAway} ${hi ? 'दिन बाद' : 'days away'}`}`)
      .join('\n')
    response += hi
      ? `📅 *आने वाले जन्मदिन*\n${upcomingList}`
      : `📅 *Upcoming Birthdays*\n${upcomingList}`
  }

  await whatsappClient.sendTextMessage(phone, response.trim())
}

// ── Count Command ───────────────────────────────────────────────────

export async function handleCountCommand(
  phone: string,
  user: { id?: string; preferredLanguage?: string | null } | null,
): Promise<void> {
  const hi = isHindi(user)

  if (!user?.id) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? '👋 कृपया पहले daxelokinrel.com पर साइन अप करें!'
        : '👋 Please sign up at daxelokinrel.com first!',
    )
    return
  }

  const families = await db.family.findMany({
    where: { members: { some: { userId: user.id } } },
    include: {
      _count: { select: { persons: true, members: true } },
    },
  })

  if (families.length === 0) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? '🌳 आपने अभी तक कोई परिवार वृक्ष नहीं बनाया है। ऐप में शुरू करें!'
        : "🌳 You haven't created a family tree yet. Start in the app!",
    )
    return
  }

  const totalMembers = families.reduce(
    (sum, f) => sum + f._count.persons,
    0,
  )
  const totalAppMembers = families.reduce(
    (sum, f) => sum + f._count.members,
    0,
  )

  // Get deceased count
  const allPersons = await db.person.findMany({
    where: {
      familyId: { in: families.map((f) => f.id) },
    },
    select: { isDeceased: true },
  })
  const deceasedCount = allPersons.filter((p) => p.isDeceased).length

  const familyDetails = families
    .map((f) => `• ${f.name}: ${f._count.persons} ${hi ? 'सदस्य' : 'members'}`)
    .join('\n')

  await whatsappClient.sendTextMessage(
    phone,
    hi
      ? `👨‍👩‍👧‍👦 *आपका परिवार वृक्ष*\n\nपरिवार: ${families.length}\nकुल सदस्य: ${totalMembers}\nऐप पर: ${totalAppMembers}\nस्वर्गीय: ${deceasedCount}\n\n${familyDetails}\n\nबढ़ते रहें! 🌳`
      : `👨‍👩‍👧‍👦 *Your Family Tree*\n\nFamilies: ${families.length}\nTotal members: ${totalMembers}\nOn the app: ${totalAppMembers}\nDeceased: ${deceasedCount}\n\n${familyDetails}\n\nKeep growing! 🌳`,
  )
}

// ── Add Command ─────────────────────────────────────────────────────

export async function handleAddCommand(
  phone: string,
  user: { id?: string; preferredLanguage?: string | null } | null,
  args: string,
): Promise<void> {
  const hi = isHindi(user)

  if (!user?.id) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? '👋 कृपया पहले daxelokinrel.com पर साइन अप करें!'
        : '👋 Please sign up at daxelokinrel.com first!',
    )
    return
  }

  // Check which families the user belongs to
  const families = await db.family.findMany({
    where: { members: { some: { userId: user.id } } },
    select: { id: true, name: true },
  })

  if (families.length === 0) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? '🌳 आपका कोई परिवार वृक्ष नहीं है। कृपया पहले ऐप में परिवार बनाएं।'
        : "🌳 You don't have a family tree yet. Please create a family in the app first.",
    )
    return
  }

  // If user provided a name, set session to ADDING_PERSON flow
  if (args) {
    // Set session state to collect more info about the person
    await sessionManager.setState(phone, SessionState.ADDING_PERSON, {
      personName: args,
      step: 'select_family',
      userId: user.id,
    })

    if (families.length === 1) {
      // Only one family — auto-select it and proceed
      await sessionManager.update(phone, {
        data: {
          personName: args,
          step: 'ask_relation',
          userId: user.id,
          familyId: families[0].id,
          familyName: families[0].name,
        },
      })

      await whatsappClient.sendInteractiveMessage(
        phone,
        hi ? '➕ सदस्य जोड़ें' : '➕ Add Member',
        hi
          ? `"${args}" को "${families[0].name}" परिवार में जोड़ रहे हैं। रिश्ता बताएं:`
          : `Adding "${args}" to the "${families[0].name}" family. What's their relationship?`,
        [
          { id: 'rel_father', title: hi ? 'पिता' : 'Father' },
          { id: 'rel_mother', title: hi ? 'माता' : 'Mother' },
          { id: 'rel_other', title: hi ? 'अन्य' : 'Other' },
        ],
        hi ? 'रिश्ता चुनें' : 'Select relationship',
      )
    } else {
      // Multiple families — ask which family
      const rows = families.map((f) => ({
        id: `family_${f.id}`,
        title: f.name,
      }))

      await whatsappClient.sendListMessage(
        phone,
        hi ? '➕ सदस्य जोड़ें' : '➕ Add Member',
        hi
          ? `"${args}" को किस परिवार में जोड़ना है?`
          : `Which family should I add "${args}" to?`,
        [{ title: hi ? 'परिवार चुनें' : 'Select Family', rows }],
        hi ? 'परिवार चुनें' : 'Select Family',
      )
    }
    return
  }

  // No name provided — ask for name
  await sessionManager.setState(phone, SessionState.ADDING_PERSON, {
    step: 'ask_name',
    userId: user.id,
  })

  await whatsappClient.sendTextMessage(
    phone,
    hi
      ? '➕ नए सदस्य का नाम बताएं:\n\nउदाहरण: "add Priya" या "जोड़ो प्रिया"'
      : '➕ Tell me the name of the new member:\n\nExample: "add Priya" or "जोड़ो प्रिया"',
  )
}

// ── Invite Command ──────────────────────────────────────────────────

export async function handleInviteCommand(
  phone: string,
  user: { id?: string; preferredLanguage?: string | null } | null,
  args: string,
): Promise<void> {
  const hi = isHindi(user)

  if (!user?.id) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? '👋 कृपया पहले daxelokinrel.com पर साइन अप करें!'
        : '👋 Please sign up at daxelokinrel.com first!',
    )
    return
  }

  // Check which families the user belongs to
  const families = await db.family.findMany({
    where: {
      members: {
        some: { userId: user.id, role: { in: ['admin', 'editor'] } },
      },
    },
    select: { id: true, name: true },
  })

  if (families.length === 0) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? '👨‍👩‍👧‍👦 आप किसी परिवार के एडमिन या एडिटर नहीं हैं। आमंत्रण भेजने के लिए एडमिन से बात करें।'
        : "👨‍👩‍👧‍👦 You're not an admin or editor of any family. Ask an admin to send invitations.",
    )
    return
  }

  if (!args) {
    // Set session state for inviting flow
    await sessionManager.setState(phone, SessionState.INVITING_FAMILY, {
      step: 'ask_phone',
      userId: user.id,
    })

    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? '📱 आमंत्रित करने के लिए फ़ोन नंबर बताएं (10 अंकों का भारतीय नंबर):\n\nउदाहरण: "invite 9876543210" या "बुलाओ 9876543210"'
        : '📱 Share the phone number to invite (10-digit Indian number):\n\nExample: "invite 9876543210" or "बुलाओ 9876543210"',
    )
    return
  }

  // Parse the phone number from args
  const invitePhone = args.replace(/\D/g, '')
  if (invitePhone.length < 10 || invitePhone.length > 12) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? '❌ अमान्य फ़ोन नंबर। कृपया 10 अंकों का भारतीय नंबर दें।'
        : '❌ Invalid phone number. Please provide a 10-digit Indian number.',
    )
    return
  }

  // If user belongs to multiple families, ask which family
  if (families.length > 1) {
    await sessionManager.setState(phone, SessionState.INVITING_FAMILY, {
      step: 'select_family',
      userId: user.id,
      invitePhone,
    })

    const rows = families.map((f) => ({
      id: `invite_family_${f.id}`,
      title: f.name,
    }))

    await whatsappClient.sendListMessage(
      phone,
      hi ? '👨‍👩‍👧‍👦 आमंत्रण भेजें' : '👨‍👩‍👧‍👦 Send Invitation',
      hi
        ? `${invitePhone} को किस परिवार में आमंत्रित करना है?`
        : `Which family should I invite ${invitePhone} to?`,
      [{ title: hi ? 'परिवार चुनें' : 'Select Family', rows }],
      hi ? 'परिवार चुनें' : 'Select Family',
    )
    return
  }

  // Single family — create invitation directly
  await createAndSendInvitation(phone, user.id, families[0].id, families[0].name, invitePhone, hi)
}

// ── Helper: Create and Send Invitation ──────────────────────────────

async function createAndSendInvitation(
  senderPhone: string,
  inviterId: string,
  familyId: string,
  familyName: string,
  recipientPhone: string,
  hi: boolean,
): Promise<void> {
  // Generate a unique invitation token
  const { v4: uuidv4 } = await import('uuid')
  const token = uuidv4()

  const invitation = await db.invitation.create({
    data: {
      token,
      familyId,
      inviterId,
      recipientPhone,
      channel: 'whatsapp',
      status: 'pending',
      expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000), // 7 days
    },
  })

  const deepLink = `https://daxelo.app/invite/${token}`

  // Send WhatsApp message to the invitee
  const formattedPhone = recipientPhone.startsWith('+')
    ? recipientPhone
    : `+91${recipientPhone}`

  try {
    await whatsappClient.sendTextMessage(
      formattedPhone,
      hi
        ? `🙏 आपको *${familyName}* परिवार में शामिल होने के लिए आमंत्रित किया गया है!\n\nअपने परिवार के साथ जुड़ें और अपना परिवार वृक्ष बनाएं।\n\nशामिल होने के लिए टैप करें: ${deepLink}`
        : `🙏 You've been invited to join the *${familyName}* family on Daxelo Kinrel!\n\nConnect with your family and build your family tree together.\n\nTap to join: ${deepLink}`,
    )

    // Update invitation as sent
    await db.invitation.update({
      where: { id: invitation.id },
      data: { whatsappSentAt: new Date() },
    })

    // Notify the inviter
    await whatsappClient.sendTextMessage(
      senderPhone,
      hi
        ? `✅ आमंत्रण ${recipientPhone} को भेज दिया गया है! वे 7 दिनों में शामिल हो सकते हैं।`
        : `✅ Invitation sent to ${recipientPhone}! They have 7 days to join.`,
    )
  } catch (error) {
    console.error('Failed to send WhatsApp invitation:', error)

    await whatsappClient.sendTextMessage(
      senderPhone,
      hi
        ? `⚠️ आमंत्रण बनाया गया लेकिन WhatsApp संदेश भेजने में समस्या हुई। वे इस लिंक से भी शामिल हो सकते हैं: ${deepLink}`
        : `⚠️ Invitation created but WhatsApp message failed to send. They can also join using this link: ${deepLink}`,
    )
  }
}

// ── Matches Command ─────────────────────────────────────────────────

export async function handleMatchesCommand(
  phone: string,
  user: { id?: string; preferredLanguage?: string | null } | null,
): Promise<void> {
  const hi = isHindi(user)

  if (!user?.id) {
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? '👋 कृपया पहले daxelokinrel.com पर साइन अप करें!'
        : '👋 Please sign up at daxelokinrel.com first!',
    )
    return
  }

  // Since there's no MatrimonialProfile model in the current schema,
  // we check for family members who could be potential matches
  // by looking at persons with relationship details
  const families = await db.family.findMany({
    where: { members: { some: { userId: user.id } } },
    include: {
      persons: {
        where: {
          isDeceased: false,
          // Looking for unmarried / matchable persons
        },
        take: 5,
      },
    },
  })

  const eligiblePersons = families.flatMap((f) =>
    f.persons
      .filter((p) => !p.isDeceased)
      .map((p) => ({ ...p, familyName: f.name })),
  )

  if (eligiblePersons.length === 0) {
    await whatsappClient.sendInteractiveMessage(
      phone,
      '💕 Matrimonial',
      hi
        ? 'आपके परिवार वृक्ष में अभी कोई मैच नहीं है। ऐप में प्रोफ़ाइल बनाएं!'
        : "No matches available yet. Create a profile in the app to start matching!",
      [{ id: 'open_matrimonial', title: hi ? 'ऐप खोलें' : 'Open App' }],
    )
    return
  }

  // Show top potential matches
  const lines = eligiblePersons.slice(0, 5).map((p, i) => {
    const age = p.dateOfBirth ? getAge(p.dateOfBirth) : '?'
    const details: string[] = []
    if (p.occupation) details.push(p.occupation)
    if (p.city) details.push(p.city)
    const detailStr = details.length > 0 ? details.join(' | ') : '—'
    return `${i + 1}. ${p.name}, ${age} — ${detailStr} (${p.familyName})`
  })

  await whatsappClient.sendTextMessage(
    phone,
    hi
      ? `💕 *संभावित मैच*\n\n${lines.join('\n')}\n\nपूरी प्रोफ़ाइल देखने और रुचि व्यक्त करने के लिए ऐप खोलें!`
      : `💕 *Potential Matches*\n\n${lines.join('\n')}\n\nOpen the app to see full profiles and express interest!`,
  )
}

// ── Language Command ────────────────────────────────────────────────

export async function handleLanguageCommand(
  phone: string,
  user: { id?: string; preferredLanguage?: string | null } | null,
  args: string,
): Promise<void> {
  // Direct language selection if a valid language code is provided
  const langMap: Record<string, string> = {
    en: 'en',
    english: 'en',
    hi: 'hi',
    hindi: 'hi',
    हिंदी: 'hi',
    te: 'te',
    telugu: 'te',
    తెలుగు: 'te',
    ta: 'ta',
    tamil: 'ta',
    தமிழ்: 'ta',
  }

  const selectedLang = langMap[args.toLowerCase().trim()]

  if (selectedLang && user?.id) {
    // Update user's preferred language
    await db.user.update({
      where: { id: user.id },
      data: { preferredLanguage: selectedLang },
    })

    await sessionManager.reset(phone)

    const langNames: Record<string, string> = {
      en: 'English',
      hi: 'हिंदी (Hindi)',
      te: 'తెలుగు (Telugu)',
      ta: 'தமிழ் (Tamil)',
    }

    await whatsappClient.sendTextMessage(
      phone,
      `✅ Language updated to ${langNames[selectedLang]}!`,
    )
    return
  }

  // No valid language provided — set session state and show language options
  await sessionManager.setState(phone, SessionState.LANGUAGE_SELECT, {
    userId: user?.id,
  })

  await whatsappClient.sendInteractiveMessage(
    phone,
    '🌐 Language / भाषा',
    'Select your preferred language / अपनी भाषा चुनें:',
    [
      { id: 'lang_en', title: 'English' },
      { id: 'lang_hi', title: 'हिंदी' },
      { id: 'lang_te', title: 'తెలుగు' },
    ],
    'தமிழ் also available in app',
  )
}

// ── Handle Flow State ───────────────────────────────────────────────

export async function handleFlowState(
  phone: string,
  session: BotSession,
  text: string,
  buttonReply: string | undefined,
  user: { id?: string; preferredLanguage?: string | null } | null,
): Promise<void> {
  const hi = isHindi(user)

  switch (session.state) {
    case SessionState.ADDING_PERSON:
      await handleAddingPersonFlow(phone, session, text, buttonReply, user)
      break

    case SessionState.SELECTING_PERSON:
      await handleSelectingPersonFlow(phone, session, text, user)
      break

    case SessionState.INVITING_FAMILY:
      await handleInvitingFamilyFlow(phone, session, text, buttonReply, user)
      break

    case SessionState.LANGUAGE_SELECT:
      await handleLanguageSelectFlow(phone, session, buttonReply, user)
      break

    default:
      // Unknown state — reset
      await sessionManager.reset(phone)
      await whatsappClient.sendTextMessage(
        phone,
        hi
          ? "सेशन एक्सपायर हो गया। फिर से शुरू करें — 'मदद' टाइप करें।"
          : "Session expired. Start again — type 'help'.",
      )
  }
}

// ── Adding Person Flow ──────────────────────────────────────────────

async function handleAddingPersonFlow(
  phone: string,
  session: BotSession,
  text: string,
  buttonReply: string | undefined,
  user: { id?: string; preferredLanguage?: string | null } | null,
): Promise<void> {
  const hi = isHindi(user)
  const data = session.data as Record<string, unknown>
  const step = data.step as string | undefined

  // Step: ask_name
  if (step === 'ask_name' && text) {
    await sessionManager.update(phone, {
      data: { ...data, personName: text, step: 'select_family' },
    })

    // Check families
    if (!user?.id) {
      await sessionManager.reset(phone)
      return
    }

    const families = await db.family.findMany({
      where: { members: { some: { userId: user.id } } },
      select: { id: true, name: true },
    })

    if (families.length === 1) {
      // Auto-select single family
      await sessionManager.update(phone, {
        data: {
          ...data,
          personName: text,
          step: 'ask_relation',
          familyId: families[0].id,
          familyName: families[0].name,
        },
      })

      await whatsappClient.sendInteractiveMessage(
        phone,
        hi ? '➕ सदस्य जोड़ें' : '➕ Add Member',
        hi
          ? `"${text}" को "${families[0].name}" परिवार में जोड़ रहे हैं। रिश्ता बताएं:`
          : `Adding "${text}" to the "${families[0].name}" family. What's their relationship?`,
        [
          { id: 'rel_father', title: hi ? 'पिता' : 'Father' },
          { id: 'rel_mother', title: hi ? 'माता' : 'Mother' },
          { id: 'rel_other', title: hi ? 'अन्य' : 'Other' },
        ],
        hi ? 'रिश्ता चुनें' : 'Select relationship',
      )
    } else {
      const rows = families.map((f) => ({
        id: `family_${f.id}`,
        title: f.name,
      }))

      await whatsappClient.sendListMessage(
        phone,
        hi ? '➕ सदस्य जोड़ें' : '➕ Add Member',
        hi
          ? `"${text}" को किस परिवार में जोड़ना है?`
          : `Which family should I add "${text}" to?`,
        [{ title: hi ? 'परिवार चुनें' : 'Select Family', rows }],
        hi ? 'परिवार चुनें' : 'Select Family',
      )
    }
    return
  }

  // Step: ask_relation (handling button reply)
  if (step === 'ask_relation' && buttonReply) {
    const relationshipMap: Record<string, string> = {
      rel_father: 'father',
      rel_mother: 'mother',
      rel_son: 'son',
      rel_daughter: 'daughter',
      rel_brother: 'brother',
      rel_sister: 'sister',
      rel_husband: 'husband',
      rel_wife: 'wife',
      rel_uncle: 'uncle',
      rel_aunt: 'aunt',
      rel_cousin: 'cousin',
      rel_grandfather: 'grandfather',
      rel_grandmother: 'grandmother',
      rel_other: 'other',
    }

    const relationship = relationshipMap[buttonReply] ?? buttonReply.replace('rel_', '')
    const personName = data.personName as string
    const familyId = data.familyId as string

    // Create the person in the database
    try {
      const person = await db.person.create({
        data: {
          name: personName,
          familyId,
          relationship,
        },
      })

      await sessionManager.reset(phone)

      await whatsappClient.sendTextMessage(
        phone,
        hi
          ? `✅ *${personName}* (${relationship}) परिवार में जोड़ दिया गया!\n\nऐप में और विवरण जोड़ें: जन्मतिथि, व्यवसाय, शहर आदि।`
          : `✅ *${personName}* (${relationship}) has been added to the family!\n\nAdd more details in the app: date of birth, occupation, city, etc.`,
      )
    } catch (error) {
      console.error('Failed to add person:', error)
      await sessionManager.reset(phone)
      await whatsappClient.sendTextMessage(
        phone,
        hi
          ? '❌ सदस्य जोड़ने में समस्या हुई। कृपया ऐप में जोड़ें।'
          : '❌ Failed to add member. Please try adding in the app.',
      )
    }
    return
  }

  // Step: ask_relation (text input for "other" relationship)
  if (step === 'ask_relation' && text && !buttonReply) {
    const personName = data.personName as string
    const familyId = data.familyId as string
    const relationship = text

    try {
      await db.person.create({
        data: {
          name: personName,
          familyId,
          relationship,
        },
      })

      await sessionManager.reset(phone)

      await whatsappClient.sendTextMessage(
        phone,
        hi
          ? `✅ *${personName}* (${relationship}) परिवार में जोड़ दिया गया!`
          : `✅ *${personName}* (${relationship}) has been added to the family!`,
      )
    } catch (error) {
      console.error('Failed to add person:', error)
      await sessionManager.reset(phone)
      await whatsappClient.sendTextMessage(
        phone,
        hi
          ? '❌ सदस्य जोड़ने में समस्या हुई।'
          : '❌ Failed to add member.',
      )
    }
    return
  }

  // Timeout or invalid state — reset
  await sessionManager.reset(phone)
  await whatsappClient.sendTextMessage(
    phone,
    hi ? '⏰ समय समाप्त। फिर से शुरू करें।' : '⏰ Session timed out. Please start again.',
  )
}

// ── Selecting Person Flow ───────────────────────────────────────────

async function handleSelectingPersonFlow(
  phone: string,
  session: BotSession,
  text: string,
  user: { id?: string; preferredLanguage?: string | null } | null,
): Promise<void> {
  const hi = isHindi(user)
  const data = session.data as Record<string, unknown>
  const matchingPersons = data.matchingPersons as Array<{ id: string; name: string }> | undefined

  if (!matchingPersons || matchingPersons.length === 0) {
    await sessionManager.reset(phone)
    await whatsappClient.sendTextMessage(
      phone,
      hi ? 'कोई मिलान नहीं मिला। फिर से खोजें।' : 'No matches found. Try searching again.',
    )
    return
  }

  // Try to match the user's text input to one of the persons
  const matchedPerson = matchingPersons.find(
    (p) => p.name.toLowerCase() === text.toLowerCase() ||
      p.name.toLowerCase().includes(text.toLowerCase()),
  )

  if (!matchedPerson) {
    const names = matchingPersons.map((p) => `• ${p.name}`).join('\n')
    await whatsappClient.sendTextMessage(
      phone,
      hi
        ? `मिलान नहीं मिला। इनमें से चुनें:\n${names}`
        : `No match found. Choose from:\n${names}`,
    )
    return
  }

  // Fetch full person details
  const person = await db.person.findUnique({
    where: { id: matchedPerson.id },
    include: { family: true },
  })

  if (!person) {
    await sessionManager.reset(phone)
    await whatsappClient.sendTextMessage(
      phone,
      hi ? 'व्यक्ति नहीं मिला।' : 'Person not found.',
    )
    return
  }

  await sessionManager.reset(phone)

  const age = person.dateOfBirth ? getAge(person.dateOfBirth) : null
  let reply = `📋 *${person.name}*\n`
  if (person.relationship) reply += `${hi ? 'रिश्ता' : 'Relationship'}: ${person.relationship}\n`
  if (age !== null) reply += `${hi ? 'उम्र' : 'Age'}: ${age}\n`
  if (person.gotra) reply += `Gotra: ${person.gotra}\n`
  if (person.occupation) reply += `${hi ? 'व्यवसाय' : 'Occupation'}: ${person.occupation}\n`
  if (person.city) reply += `${hi ? 'शहर' : 'City'}: ${person.city}\n`
  reply += `${hi ? 'परिवार' : 'Family'}: ${person.family.name}`

  await whatsappClient.sendTextMessage(phone, reply)
}

// ── Inviting Family Flow ────────────────────────────────────────────

async function handleInvitingFamilyFlow(
  phone: string,
  session: BotSession,
  text: string,
  buttonReply: string | undefined,
  user: { id?: string; preferredLanguage?: string | null } | null,
): Promise<void> {
  const hi = isHindi(user)
  const data = session.data as Record<string, unknown>
  const step = data.step as string | undefined

  // Step: ask_phone
  if (step === 'ask_phone' && text) {
    const invitePhone = text.replace(/\D/g, '')
    if (invitePhone.length < 10 || invitePhone.length > 12) {
      await whatsappClient.sendTextMessage(
        phone,
        hi
          ? '❌ अमान्य फ़ोन नंबर। कृपया 10 अंकों का भारतीय नंबर दें।'
          : '❌ Invalid phone number. Please provide a 10-digit Indian number.',
      )
      return
    }

    if (!user?.id) {
      await sessionManager.reset(phone)
      return
    }

    const families = await db.family.findMany({
      where: {
        members: { some: { userId: user.id, role: { in: ['admin', 'editor'] } } },
      },
      select: { id: true, name: true },
    })

    if (families.length === 1) {
      await createAndSendInvitation(phone, user.id, families[0].id, families[0].name, invitePhone, hi)
      await sessionManager.reset(phone)
    } else {
      await sessionManager.update(phone, {
        data: { ...data, invitePhone, step: 'select_family' },
      })

      const rows = families.map((f) => ({
        id: `invite_family_${f.id}`,
        title: f.name,
      }))

      await whatsappClient.sendListMessage(
        phone,
        hi ? '👨‍👩‍👧‍👦 आमंत्रण भेजें' : '👨‍👩‍👧‍👦 Send Invitation',
        hi
          ? `${invitePhone} को किस परिवार में आमंत्रित करना है?`
          : `Which family should I invite ${invitePhone} to?`,
        [{ title: hi ? 'परिवार चुनें' : 'Select Family', rows }],
        hi ? 'परिवार चुनें' : 'Select Family',
      )
    }
    return
  }

  // Timeout or invalid state
  await sessionManager.reset(phone)
  await whatsappClient.sendTextMessage(
    phone,
    hi ? '⏰ समय समाप्त। फिर से शुरू करें।' : '⏰ Session timed out. Please start again.',
  )
}

// ── Language Select Flow ────────────────────────────────────────────

async function handleLanguageSelectFlow(
  phone: string,
  session: BotSession,
  buttonReply: string | undefined,
  user: { id?: string; preferredLanguage?: string | null } | null,
): Promise<void> {
  if (!buttonReply) {
    await sessionManager.reset(phone)
    return
  }

  const langMap: Record<string, string> = {
    lang_en: 'en',
    lang_hi: 'hi',
    lang_te: 'te',
    lang_ta: 'ta',
  }

  const selectedLang = langMap[buttonReply]
  if (!selectedLang) {
    await sessionManager.reset(phone)
    return
  }

  if (user?.id) {
    await db.user.update({
      where: { id: user.id },
      data: { preferredLanguage: selectedLang },
    })
  }

  await sessionManager.reset(phone)

  const langNames: Record<string, string> = {
    en: 'English',
    hi: 'हिंदी (Hindi)',
    te: 'తెలుగు (Telugu)',
    ta: 'தமிழ் (Tamil)',
  }

  await whatsappClient.sendTextMessage(
    phone,
    `✅ Language updated to ${langNames[selectedLang]}!`,
  )
}

// ── Handle Button Reply ─────────────────────────────────────────────

export async function handleButtonReply(
  phone: string,
  buttonId: string,
  user: { id?: string; preferredLanguage?: string | null } | null,
): Promise<void> {
  const hi = isHindi(user)

  // Command shortcut buttons
  switch (buttonId) {
    case 'cmd_help':
      await handleHelpCommand(phone, user)
      break

    case 'cmd_birthday':
      await handleBirthdayCommand(phone, user)
      break

    case 'cmd_count':
      await handleCountCommand(phone, user)
      break

    case 'cmd_who':
      await whatsappClient.sendTextMessage(
        phone,
        hi
          ? 'किसके बारे में जानना चाहते हैं? उदाहरण: "who is Priya"'
          : "Who do you want to know about? Example: 'who is Priya'",
      )
      break

    case 'cmd_add':
      await handleAddCommand(phone, user, '')
      break

    case 'cmd_invite':
      await handleInviteCommand(phone, user, '')
      break

    case 'cmd_matches':
      await handleMatchesCommand(phone, user)
      break

    case 'cmd_relation':
      await whatsappClient.sendTextMessage(
        phone,
        hi
          ? 'रिश्ता जानने के लिए नाम बताएं। उदाहरण: "relation Priya"'
          : "Share a name to find their relationship. Example: 'relation Priya'",
      )
      break

    case 'cmd_language':
      await handleLanguageCommand(phone, user, '')
      break

    case 'open_matrimonial':
      await whatsappClient.sendTextMessage(
        phone,
        hi
          ? '💕 ऐप खोलें: https://daxelokinrel.com/matrimonial'
          : '💕 Open the app: https://daxelokinrel.com/matrimonial',
      )
      break

    // Relationship buttons from add flow
    case 'rel_father':
    case 'rel_mother':
    case 'rel_son':
    case 'rel_daughter':
    case 'rel_brother':
    case 'rel_sister':
    case 'rel_husband':
    case 'rel_wife':
    case 'rel_uncle':
    case 'rel_aunt':
    case 'rel_cousin':
    case 'rel_grandfather':
    case 'rel_grandmother':
    case 'rel_other': {
      const session = await sessionManager.getOrCreate(phone)
      if (session.state === SessionState.ADDING_PERSON) {
        await handleAddingPersonFlow(phone, session, '', buttonId, user)
      } else {
        await whatsappClient.sendTextMessage(
          phone,
          hi
            ? "सेशन एक्सपायर हो गया। फिर से 'add' कमांड टाइप करें।"
            : "Session expired. Type 'add' again to start.",
        )
      }
      break
    }

    default:
      await whatsappClient.sendTextMessage(
        phone,
        hi
          ? "मुझे समझ नहीं आया। 'मदद' टाइप करें।"
          : "I didn't understand that. Type 'help'.",
      )
  }
}

// ── Handle List Reply ───────────────────────────────────────────────

export async function handleListReply(
  phone: string,
  listId: string,
  user: { id?: string; preferredLanguage?: string | null } | null,
): Promise<void> {
  const hi = isHindi(user)

  // Family selection for add command
  if (listId.startsWith('family_')) {
    const familyId = listId.replace('family_', '')
    const session = await sessionManager.getOrCreate(phone)

    if (session.state === SessionState.ADDING_PERSON) {
      const data = session.data as Record<string, unknown>
      const personName = data.personName as string

      // Get family name
      const family = await db.family.findUnique({
        where: { id: familyId },
        select: { name: true },
      })

      if (!family) {
        await sessionManager.reset(phone)
        await whatsappClient.sendTextMessage(
          phone,
          hi ? '❌ परिवार नहीं मिला।' : '❌ Family not found.',
        )
        return
      }

      await sessionManager.update(phone, {
        data: {
          ...data,
          step: 'ask_relation',
          familyId,
          familyName: family.name,
        },
      })

      await whatsappClient.sendInteractiveMessage(
        phone,
        hi ? '➕ सदस्य जोड़ें' : '➕ Add Member',
        hi
          ? `"${personName}" को "${family.name}" परिवार में जोड़ रहे हैं। रिश्ता बताएं:`
          : `Adding "${personName}" to the "${family.name}" family. What's their relationship?`,
        [
          { id: 'rel_father', title: hi ? 'पिता' : 'Father' },
          { id: 'rel_mother', title: hi ? 'माता' : 'Mother' },
          { id: 'rel_other', title: hi ? 'अन्य' : 'Other' },
        ],
        hi ? 'रिश्ता चुनें' : 'Select relationship',
      )
      return
    }

    await sessionManager.reset(phone)
    return
  }

  // Family selection for invite command
  if (listId.startsWith('invite_family_')) {
    const familyId = listId.replace('invite_family_', '')
    const session = await sessionManager.getOrCreate(phone)

    if (session.state === SessionState.INVITING_FAMILY) {
      const data = session.data as Record<string, unknown>
      const invitePhone = data.invitePhone as string

      const family = await db.family.findUnique({
        where: { id: familyId },
        select: { name: true },
      })

      if (!family) {
        await sessionManager.reset(phone)
        await whatsappClient.sendTextMessage(
          phone,
          hi ? '❌ परिवार नहीं मिला।' : '❌ Family not found.',
        )
        return
      }

      await createAndSendInvitation(phone, user?.id ?? '', familyId, family.name, invitePhone, hi)
      await sessionManager.reset(phone)
      return
    }

    await sessionManager.reset(phone)
    return
  }

  // Standard command list items
  switch (listId) {
    case 'cmd_who':
      await whatsappClient.sendTextMessage(
        phone,
        hi
          ? 'किसके बारे में जानना चाहते हैं? उदाहरण: "who is Priya"'
          : "Who do you want to know about? Example: 'who is Priya'",
      )
      break

    case 'cmd_birthday':
      await handleBirthdayCommand(phone, user)
      break

    case 'cmd_count':
      await handleCountCommand(phone, user)
      break

    case 'cmd_relation':
      await whatsappClient.sendTextMessage(
        phone,
        hi
          ? 'रिश्ता जानने के लिए नाम बताएं। उदाहरण: "relation Priya"'
          : "Share a name to find their relationship. Example: 'relation Priya'",
      )
      break

    case 'cmd_add':
      await handleAddCommand(phone, user, '')
      break

    case 'cmd_invite':
      await handleInviteCommand(phone, user, '')
      break

    case 'cmd_matches':
      await handleMatchesCommand(phone, user)
      break

    case 'cmd_language':
      await handleLanguageCommand(phone, user, '')
      break

    case 'cmd_help':
      await handleHelpCommand(phone, user)
      break

    default:
      await whatsappClient.sendTextMessage(
        phone,
        hi
          ? "मुझे समझ नहीं आया। 'मदद' टाइप करें।"
          : "I didn't understand that. Type 'help'.",
      )
  }
}
