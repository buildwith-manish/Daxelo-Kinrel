import { NextRequest } from 'next/server';
import { db } from '@/lib/db';
import { success, created, error } from '@/packages/api';

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const userId = searchParams.get('userId');
    const limit = Math.min(parseInt(searchParams.get('limit') ?? '20'), 100);
    const offset = parseInt(searchParams.get('offset') ?? '0');

    if (!userId) return error('MISSING_REQUIRED_FIELD', 'userId is required', 400);

    const where: any = { userId };
    const readFilter = searchParams.get('read');
    if (readFilter !== null && readFilter !== '') where.read = readFilter === 'true';

    const [notifications, unreadCount] = await Promise.all([
      db.notification.findMany({ where, orderBy: { createdAt: 'desc' }, take: limit, skip: offset, include: { updates: { orderBy: { createdAt: 'desc' } } } }),
      db.notification.count({ where: { userId, read: false } }),
    ]);

    return success({ notifications: notifications.map(n => ({ ...n, channels: JSON.parse(n.channels) })), unreadCount, limit, offset });
  } catch (err) {
    console.error('[Notifications GET] Error:', err);
    return error('INTERNAL_ERROR', 'Failed to fetch notifications', 500);
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const { userId, notificationIds } = await request.json();
    if (!userId) return error('MISSING_REQUIRED_FIELD', 'userId is required', 400);

    const where: any = { userId, read: false };
    if (notificationIds?.length) where.id = { in: notificationIds };
    const result = await db.notification.updateMany({ where, data: { read: true, readAt: new Date() } });

    return success({ updated: result.count });
  } catch (err) {
    console.error('[Notifications PATCH] Error:', err);
    return error('INTERNAL_ERROR', 'Failed to update notifications', 500);
  }
}
