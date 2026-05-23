// DAXELO KINREL — Pack 08: Moderation Rule Management
// GET — List all rules
// POST — Create custom rule
// PATCH — Toggle rule active/inactive

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { isUserModerator } from '@/lib/moderation/auto-rules'

// ── GET: List All Rules ─────────────────────────────────────────────────

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const userId = searchParams.get('userId')
    const category = searchParams.get('category') || undefined
    const activeOnly = searchParams.get('activeOnly') === 'true'

    // Auth check
    if (!userId) {
      return NextResponse.json({ error: 'userId is required' }, { status: 400 })
    }

    const isMod = await isUserModerator(userId)
    if (!isMod) {
      return NextResponse.json({ error: 'Access denied. Moderator role required.' }, { status: 403 })
    }

    // Build where clause
    const where: Record<string, unknown> = {}
    if (category) where.category = category
    if (activeOnly) where.isActive = true

    const rules = await db.moderationRule.findMany({
      where,
      orderBy: [
        { priority: 'desc' },
        { name: 'asc' },
      ],
    })

    const activeCount = rules.filter(r => r.isActive).length
    const inactiveCount = rules.filter(r => !r.isActive).length

    // Group by category
    const byCategory: Record<string, typeof rules> = {}
    for (const rule of rules) {
      if (!byCategory[rule.category]) byCategory[rule.category] = []
      byCategory[rule.category].push(rule)
    }

    return NextResponse.json({
      rules,
      stats: {
        total: rules.length,
        active: activeCount,
        inactive: inactiveCount,
        categories: Object.keys(byCategory).length,
      },
      byCategory,
    })

  } catch (error) {
    console.error('Rule list error:', error)
    return NextResponse.json({ error: 'Failed to fetch rules' }, { status: 500 })
  }
}

// ── POST: Create Custom Rule ────────────────────────────────────────────

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { name, description, contentType, category, condition, action, priority, createdBy } = body

    // Validation
    if (!name || !category || !condition || !action) {
      return NextResponse.json(
        { error: 'Missing required fields: name, category, condition, action' },
        { status: 400 },
      )
    }

    // Auth check
    if (!createdBy) {
      return NextResponse.json({ error: 'createdBy (userId) is required' }, { status: 400 })
    }

    const isMod = await isUserModerator(createdBy)
    if (!isMod) {
      return NextResponse.json({ error: 'Access denied. Moderator role required.' }, { status: 403 })
    }

    const validActions = ['allow', 'allow_with_flag', 'quarantine', 'reject', 'escalate', 'report_to_authorities']
    if (!validActions.includes(action)) {
      return NextResponse.json(
        { error: `Invalid action. Must be one of: ${validActions.join(', ')}` },
        { status: 400 },
      )
    }

    const validPriorities = ['low', 'normal', 'high', 'urgent', 'critical']
    if (priority && !validPriorities.includes(priority)) {
      return NextResponse.json(
        { error: `Invalid priority. Must be one of: ${validPriorities.join(', ')}` },
        { status: 400 },
      )
    }

    // Check for duplicate name
    const existing = await db.moderationRule.findFirst({ where: { name } })
    if (existing) {
      return NextResponse.json(
        { error: `Rule with name "${name}" already exists` },
        { status: 409 },
      )
    }

    // Create the rule
    const rule = await db.moderationRule.create({
      data: {
        name,
        description: description || null,
        contentType: contentType || null,
        category,
        condition,
        action,
        priority: priority || 'normal',
        isActive: true,
        createdBy,
      },
    })

    // Write audit log
    await db.moderationAuditLog.create({
      data: {
        action: 'classify',
        contentType: 'rule',
        contentId: rule.id,
        actorType: 'human_moderator',
        actorId: createdBy,
        result: 'allow',
        reason: `Created rule: ${name}`,
        metadata: JSON.stringify({ ruleId: rule.id, category, action }),
      },
    })

    return NextResponse.json({
      rule,
      message: 'Rule created successfully',
    }, { status: 201 })

  } catch (error) {
    console.error('Rule creation error:', error)
    return NextResponse.json({ error: 'Failed to create rule' }, { status: 500 })
  }
}

// ── PATCH: Toggle Rule Active/Inactive ──────────────────────────────────

export async function PATCH(request: NextRequest) {
  try {
    const body = await request.json()
    const { ruleId, isActive, userId } = body

    // Validation
    if (!ruleId || isActive === undefined || !userId) {
      return NextResponse.json(
        { error: 'Missing required fields: ruleId, isActive, userId' },
        { status: 400 },
      )
    }

    // Auth check
    const isMod = await isUserModerator(userId)
    if (!isMod) {
      return NextResponse.json({ error: 'Access denied. Moderator role required.' }, { status: 403 })
    }

    // Check rule exists
    const rule = await db.moderationRule.findUnique({ where: { id: ruleId } })
    if (!rule) {
      return NextResponse.json({ error: 'Rule not found' }, { status: 404 })
    }

    // Toggle active status
    const updated = await db.moderationRule.update({
      where: { id: ruleId },
      data: { isActive: Boolean(isActive) },
    })

    // Write audit log
    await db.moderationAuditLog.create({
      data: {
        action: 'classify',
        contentType: 'rule',
        contentId: ruleId,
        actorType: 'human_moderator',
        actorId: userId,
        result: isActive ? 'allow' : 'reject',
        reason: `Rule "${rule.name}" ${isActive ? 'activated' : 'deactivated'}`,
        metadata: JSON.stringify({ ruleId, isActive, ruleName: rule.name }),
      },
    })

    return NextResponse.json({
      rule: updated,
      message: `Rule "${rule.name}" has been ${isActive ? 'activated' : 'deactivated'}`,
    })

  } catch (error) {
    console.error('Rule toggle error:', error)
    return NextResponse.json({ error: 'Failed to toggle rule' }, { status: 500 })
  }
}
