// DAXELO KINREL — Pack 10: Admin Dashboard Stats API
// GET /api/admin — Requires role === 'admin'

import { NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'

export async function GET() {
  const session = await getServerSession(authOptions)
  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  // Check admin role
  if ((session.user as Record<string, unknown>).role !== 'admin') {
    return NextResponse.json({ error: 'Forbidden — admin access required' }, { status: 403 })
  }

  try {
    const [totalUsers, totalFamilies, totalPersons, totalTickets] = await Promise.all([
      db.user.count(),
      db.family.count(),
      db.person.count({ where: { deletedAt: null } }),
      db.supportTicket.count(),
    ])

    // Additional stats
    const [activeSubscriptions, pendingInvitations, openTickets, totalRelationships] = await Promise.all([
      db.subscription.count({ where: { status: 'active' } }),
      db.invitation.count({ where: { status: 'pending' } }),
      db.supportTicket.count({ where: { status: { in: ['open', 'in_progress'] } } }),
      db.relationship.count(),
    ])

    // Users by role
    const usersByRole = await db.user.groupBy({
      by: ['role'],
      _count: { id: true },
    })

    // Tickets by status
    const ticketsByStatus = await db.supportTicket.groupBy({
      by: ['status'],
      _count: { id: true },
    })

    return NextResponse.json({
      stats: {
        totalUsers,
        totalFamilies,
        totalPersons,
        totalTickets,
        activeSubscriptions,
        pendingInvitations,
        openTickets,
        totalRelationships,
      },
      breakdown: {
        usersByRole: usersByRole.map((r) => ({ role: r.role, count: r._count.id })),
        ticketsByStatus: ticketsByStatus.map((t) => ({ status: t.status, count: t._count.id })),
      },
    })
  } catch (error) {
    console.error('[Admin Stats] Error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
