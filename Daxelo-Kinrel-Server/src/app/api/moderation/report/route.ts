// DAXELO KINREL — Pack 08: Content Reporting Endpoint
// POST — Submit content report with validation

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

// ── Valid Report Reasons ────────────────────────────────────────────────

const VALID_REASONS = [
  'spam',
  'harassment',
  'hate_speech',
  'caste_reference',
  'misinformation',
  'sexual_content',
  'violence',
  'impersonation',
  'pii_exposure',
  'other',
]

const VALID_TARGET_TYPES = ['post', 'comment', 'community', 'user']

const MAX_REPORTS_PER_USER_PER_HOUR = 10

// ── POST: Submit Content Report ─────────────────────────────────────────

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { reporterId, targetType, targetId, reason, description } = body

    // Validation
    if (!reporterId || !targetType || !targetId || !reason) {
      return NextResponse.json(
        { error: 'Missing required fields: reporterId, targetType, targetId, reason' },
        { status: 400 },
      )
    }

    if (!VALID_TARGET_TYPES.includes(targetType)) {
      return NextResponse.json(
        { error: `Invalid target type. Must be one of: ${VALID_TARGET_TYPES.join(', ')}` },
        { status: 400 },
      )
    }

    if (!VALID_REASONS.includes(reason)) {
      return NextResponse.json(
        { error: `Invalid report reason. Must be one of: ${VALID_REASONS.join(', ')}` },
        { status: 400 },
      )
    }

    // Check reporter exists
    const reporter = await db.user.findUnique({ where: { id: reporterId } })
    if (!reporter) {
      return NextResponse.json({ error: 'Reporter not found' }, { status: 404 })
    }

    // Rate limit: max 10 reports per user per hour
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000)
    const recentReports = await db.contentReport.count({
      where: {
        reporterId,
        createdAt: { gte: oneHourAgo },
      },
    })

    if (recentReports >= MAX_REPORTS_PER_USER_PER_HOUR) {
      return NextResponse.json(
        { error: 'Rate limit exceeded. Maximum 10 reports per hour.' },
        { status: 429 },
      )
    }

    // Dedup: same user reporting same content
    const existingReport = await db.contentReport.findFirst({
      where: {
        reporterId,
        targetType,
        targetId,
        status: { in: ['pending', 'reviewing'] },
      },
    })

    if (existingReport) {
      return NextResponse.json(
        { error: 'You have already reported this content and it is under review.', reportId: existingReport.id },
        { status: 409 },
      )
    }

    // Create the report
    const report = await db.contentReport.create({
      data: {
        reporterId,
        targetType,
        targetId,
        reason,
        description: description || null,
        status: 'pending',
      },
    })

    // Also create a moderation case for the report
    await db.moderationCase.create({
      data: {
        contentType: targetType,
        contentId: targetId,
        contentPreview: description ? description.substring(0, 500) : null,
        authorId: 'unknown', // Will be filled during review
        category: reason,
        confidence: 0.5, // User reports start at medium confidence
        autoAction: 'allow_with_flag',
        flaggedCategories: JSON.stringify([reason]),
        status: 'pending',
        priority: reason === 'sexual_content' || reason === 'violence' ? 'urgent' : 'normal',
        source: 'user_report',
        reporterId,
        reportReason: reason,
        reportDetails: description || null,
      },
    })

    return NextResponse.json({
      id: report.id,
      status: report.status,
      message: 'Report submitted successfully. Our moderation team will review it.',
    }, { status: 201 })

  } catch (error) {
    console.error('Content report error:', error)
    return NextResponse.json(
      { error: 'Failed to submit report' },
      { status: 500 },
    )
  }
}
