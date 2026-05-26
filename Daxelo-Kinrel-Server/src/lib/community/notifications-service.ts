// DAXELO KINREL — Pack 09: Community Notification Service
// Unified notification creation with preference checks, quiet hours, and Indian festival greetings

import { db } from '@/lib/db';

// ── Types ────────────────────────────────────────────────────────────

export interface CreateNotificationParams {
  userId: string;
  eventType: string;
  title: string;
  body: string;
  familyId?: string;
  personId?: string;
  actionUrl?: string;
  priority?: 'critical' | 'high' | 'normal' | 'low';
  channels?: string[];
}

export interface IndianFestival {
  name: string;
  nameHi: string;
  date: string; // MM-DD format
  greeting: string;
  greetingHi: string;
  religion: string[];
}

// ── Notification Types ───────────────────────────────────────────────

export const NOTIFICATION_TYPES: Record<string, {
  label: string;
  defaultChannels: string[];
  defaultPriority: string;
}> = {
  birthday_reminder: { label: 'Birthday Reminder', defaultChannels: ['inApp', 'push'], defaultPriority: 'normal' },
  anniversary_reminder: { label: 'Anniversary Reminder', defaultChannels: ['inApp', 'push'], defaultPriority: 'normal' },
  new_member: { label: 'New Family Member', defaultChannels: ['inApp'], defaultPriority: 'normal' },
  family_invite: { label: 'Family Invitation', defaultChannels: ['inApp', 'push', 'email'], defaultPriority: 'high' },
  invite_accepted: { label: 'Invitation Accepted', defaultChannels: ['inApp'], defaultPriority: 'normal' },
  community_post: { label: 'Community Post', defaultChannels: ['inApp'], defaultPriority: 'low' },
  community_event: { label: 'Community Event', defaultChannels: ['inApp', 'push'], defaultPriority: 'normal' },
  community_join: { label: 'Community Join', defaultChannels: ['inApp'], defaultPriority: 'low' },
  event_reminder: { label: 'Event Reminder', defaultChannels: ['inApp', 'push'], defaultPriority: 'high' },
  event_rsvp: { label: 'Event RSVP', defaultChannels: ['inApp'], defaultPriority: 'low' },
  new_comment: { label: 'New Comment', defaultChannels: ['inApp'], defaultPriority: 'low' },
  new_reaction: { label: 'New Reaction', defaultChannels: ['inApp'], defaultPriority: 'low' },
  milestone_reached: { label: 'Milestone Reached', defaultChannels: ['inApp', 'push'], defaultPriority: 'normal' },
  badge_earned: { label: 'Badge Earned', defaultChannels: ['inApp', 'push'], defaultPriority: 'normal' },
  connection_suggestion: { label: 'Connection Suggestion', defaultChannels: ['inApp'], defaultPriority: 'low' },
  relationship_discovery: { label: 'Relationship Discovery', defaultChannels: ['inApp', 'push'], defaultPriority: 'high' },
  memorial_announcement: { label: 'Memorial Announcement', defaultChannels: ['inApp', 'push'], defaultPriority: 'high' },
  festival_greeting: { label: 'Festival Greeting', defaultChannels: ['inApp', 'push'], defaultPriority: 'normal' },
  shraddh_reminder: { label: 'Shraddh Reminder', defaultChannels: ['inApp', 'push'], defaultPriority: 'high' },
  privacy_alert: { label: 'Privacy Alert', defaultChannels: ['inApp', 'push', 'email'], defaultPriority: 'critical' },
};

// ── Indian Festivals ─────────────────────────────────────────────────

export const INDIAN_FESTIVALS: IndianFestival[] = [
  { name: 'Makar Sankranti', nameHi: 'मकर संक्रांति', date: '01-14', greeting: 'Happy Makar Sankranti!', greetingHi: 'मकर संक्रांति की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Pongal', nameHi: 'पोंगल', date: '01-15', greeting: 'Happy Pongal!', greetingHi: 'पोंगल की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Republic Day', nameHi: 'गणतंत्र दिवस', date: '01-26', greeting: 'Happy Republic Day!', greetingHi: 'गणतंत्र दिवस की शुभकामनाएं!', religion: ['all'] },
  { name: 'Vasant Panchami', nameHi: 'वसंत पंचमी', date: '02-14', greeting: 'Happy Vasant Panchami!', greetingHi: 'वसंत पंचमी की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Maha Shivaratri', nameHi: 'महाशिवरात्रि', date: '02-26', greeting: 'Happy Maha Shivaratri!', greetingHi: 'महाशिवरात्रि की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Holi', nameHi: 'होली', date: '03-14', greeting: 'Happy Holi!', greetingHi: 'होली की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Ugadi', nameHi: 'उगादी', date: '03-30', greeting: 'Happy Ugadi!', greetingHi: 'उगादी की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Ram Navami', nameHi: 'राम नवमी', date: '04-06', greeting: 'Happy Ram Navami!', greetingHi: 'राम नवमी की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Mahavir Jayanti', nameHi: 'महावीर जयंती', date: '04-10', greeting: 'Happy Mahavir Jayanti!', greetingHi: 'महावीर जयंती की शुभकामनाएं!', religion: ['jain'] },
  { name: 'Eid ul-Fitr', nameHi: 'ईद उल-फित्र', date: '04-10', greeting: 'Eid Mubarak!', greetingHi: 'ईद मुबारक!', religion: ['muslim'] },
  { name: 'Baisakhi', nameHi: 'बैसाखी', date: '04-13', greeting: 'Happy Baisakhi!', greetingHi: 'बैसाखी की शुभकामनाएं!', religion: ['sikh', 'hindu'] },
  { name: 'Buddha Purnima', nameHi: 'बुद्ध पूर्णिमा', date: '05-12', greeting: 'Happy Buddha Purnima!', greetingHi: 'बुद्ध पूर्णिमा की शुभकामनाएं!', religion: ['buddhist'] },
  { name: 'Raksha Bandhan', nameHi: 'रक्षा बंधन', date: '08-09', greeting: 'Happy Raksha Bandhan!', greetingHi: 'रक्षा बंधन की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Janmashtami', nameHi: 'जन्माष्टमी', date: '08-16', greeting: 'Happy Janmashtami!', greetingHi: 'जन्माष्टमी की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Ganesh Chaturthi', nameHi: 'गणेश चतुर्थी', date: '08-27', greeting: 'Happy Ganesh Chaturthi!', greetingHi: 'गणेश चतुर्थी की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Onam', nameHi: 'ओणम', date: '09-06', greeting: 'Happy Onam!', greetingHi: 'ओणम की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Navratri', nameHi: 'नवरात्रि', date: '10-03', greeting: 'Happy Navratri!', greetingHi: 'नवरात्रि की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Dussehra', nameHi: 'दशहरा', date: '10-12', greeting: 'Happy Dussehra!', greetingHi: 'दशहरा की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Karwa Chauth', nameHi: 'करवा चौथ', date: '10-20', greeting: 'Happy Karwa Chauth!', greetingHi: 'करवा चौथ की शुभकामनाएं!', religion: ['hindu'] },
  { name: 'Diwali', nameHi: 'दीवाली', date: '10-29', greeting: 'Happy Diwali!', greetingHi: 'दीवाली की शुभकामनाएं!', religion: ['hindu', 'jain', 'sikh'] },
  { name: 'Guru Nanak Jayanti', nameHi: 'गुरु नानक जयंती', date: '11-05', greeting: 'Happy Guru Nanak Jayanti!', greetingHi: 'गुरु नानक जयंती की शुभकामनाएं!', religion: ['sikh'] },
  { name: 'Christmas', nameHi: 'क्रिसमस', date: '12-25', greeting: 'Merry Christmas!', greetingHi: 'क्रिसमस की शुभकामनाएं!', religion: ['christian'] },
];

// ── Core Functions ───────────────────────────────────────────────────

/**
 * Create a notification with preference checks and quiet hours
 */
export async function createNotification(
  params: CreateNotificationParams
): Promise<Awaited<ReturnType<typeof db.notification.create>>> {
  // Check if we should send this notification
  const shouldSend = await shouldSendNotification(params.userId, params.eventType);
  if (!shouldSend) {
    // Still create the notification as read (silent)
    return db.notification.create({
      data: {
        userId: params.userId,
        eventType: params.eventType,
        title: params.title,
        body: params.body,
        familyId: params.familyId,
        personId: params.personId,
        channels: JSON.stringify([]),
        priority: params.priority ?? 'normal',
        read: true,
        readAt: new Date(),
        actionUrl: params.actionUrl,
      },
    });
  }

  const typeConfig = NOTIFICATION_TYPES[params.eventType];
  const channels = params.channels ?? typeConfig?.defaultChannels ?? ['inApp'];
  const priority = params.priority ?? typeConfig?.defaultPriority ?? 'normal';

  return db.notification.create({
    data: {
      userId: params.userId,
      eventType: params.eventType,
      title: params.title,
      body: params.body,
      familyId: params.familyId,
      personId: params.personId,
      channels: JSON.stringify(channels),
      priority,
      actionUrl: params.actionUrl,
    },
  });
}

/**
 * Check if we should send a notification based on user preferences
 */
export async function shouldSendNotification(
  userId: string,
  eventType: string
): Promise<boolean> {
  const prefs = await db.notificationPreference.findUnique({
    where: { userId_eventType: { userId, eventType } },
  });

  if (!prefs) return true; // No prefs = send by default

  // Check if at least one channel is enabled
  if (!prefs.inApp && !prefs.push && !prefs.whatsapp && !prefs.email) {
    return false;
  }

  // Check quiet hours
  if (isInQuietHours(prefs)) {
    // Critical notifications bypass quiet hours
    const typeConfig = NOTIFICATION_TYPES[eventType];
    if (typeConfig?.defaultPriority === 'critical') return true;
    return false;
  }

  return true;
}

/**
 * Check if current time is within the user's quiet hours
 * Timezone-aware using the user's configured timezone
 */
export function isInQuietHours(prefs: {
  quietHoursStart?: string | null;
  quietHoursEnd?: string | null;
  quietHoursTimezone: string;
}): boolean {
  if (!prefs.quietHoursStart || !prefs.quietHoursEnd) return false;

  try {
    const now = new Date();
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: prefs.quietHoursTimezone || 'Asia/Kolkata',
      hour: 'numeric',
      minute: 'numeric',
      hour12: false,
    });

    const currentTimeStr = formatter.format(now);
    const [currentHour, currentMinute] = currentTimeStr.split(':').map(Number);
    const currentMinutes = currentHour * 60 + currentMinute;

    const [startHour, startMinute] = prefs.quietHoursStart.split(':').map(Number);
    const startMinutes = startHour * 60 + startMinute;

    const [endHour, endMinute] = prefs.quietHoursEnd.split(':').map(Number);
    const endMinutes = endHour * 60 + endMinute;

    // Handle overnight quiet hours (e.g., 22:00 to 08:00)
    if (startMinutes > endMinutes) {
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }

    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  } catch {
    return false;
  }
}

/**
 * Send festival greetings to all users (for daily cron)
 * Returns the number of greetings sent
 */
export async function sendFestivalGreetings(): Promise<number> {
  const today = new Date();
  const mmdd = `${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

  const todayFestivals = INDIAN_FESTIVALS.filter((f) => f.date === mmdd);
  if (todayFestivals.length === 0) return 0;

  const users = await db.user.findMany({
    select: { id: true, preferredLanguage: true },
  });

  let sentCount = 0;
  for (const user of users) {
    for (const festival of todayFestivals) {
      const greeting = user.preferredLanguage === 'hi' ? festival.greetingHi : festival.greeting;
      const title = user.preferredLanguage === 'hi' ? festival.nameHi : festival.name;

      await createNotification({
        userId: user.id,
        eventType: 'festival_greeting',
        title,
        body: greeting,
        priority: 'normal',
      });
      sentCount++;
    }
  }

  return sentCount;
}

/**
 * Mark all notifications as read for a user
 */
export async function markAllRead(userId: string): Promise<void> {
  await db.notification.updateMany({
    where: { userId, read: false },
    data: { read: true, readAt: new Date() },
  });
}

/**
 * Get unread notification count for a user
 */
export async function getUnreadCount(userId: string): Promise<number> {
  return db.notification.count({
    where: { userId, read: false },
  });
}
