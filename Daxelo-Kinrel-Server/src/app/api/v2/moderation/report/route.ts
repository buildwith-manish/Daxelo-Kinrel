import { NextRequest } from 'next/server';
import { db } from '@/lib/db';
import { success, created, error } from '@/packages/api';

const VALID_REASONS = ['spam', 'harassment', 'hate_speech', 'caste_reference', 'misinformation', 'sexual_content', 'violence', 'impersonation', 'pii_exposure', 'other'];

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { reporterId, targetType, targetId, reason, description } = body;

    if (!reporterId || !targetType || !targetId || !reason) return error('MISSING_REQUIRED_FIELD', 'reporterId, targetType, targetId, reason required', 400);
    if (!VALID_REASONS.includes(reason)) return error('INVALID_PARAMETER', `Invalid reason. Valid: ${VALID_REASONS.join(', ')}`, 400);

    // Rate limit: 10 reports per user per hour
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    const recentCount = await db.contentReport.count({ where: { reporterId, createdAt: { gte: oneHourAgo } } });
    if (recentCount >= 10) return error('RATE_LIMITED', 'Maximum 10 reports per hour', 429);

    // Dedup check
    const existing = await db.contentReport.findFirst({ where: { reporterId, targetType, targetId, status: { in: ['pending', 'reviewing'] } } });
    if (existing) return error('CONFLICT', 'Already reported and under review', 409);

    const report = await db.contentReport.create({ data: { reporterId, targetType, targetId, reason, description: description || null, status: 'pending' } });

    return created({ id: report.id, status: report.status, message: 'Report submitted successfully' });
  } catch (err) {
    console.error('[Report POST] Error:', err);
    return error('INTERNAL_ERROR', 'Failed to submit report', 500);
  }
}
