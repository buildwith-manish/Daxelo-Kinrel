// DAXELO KINREL — System Status API
// Pack 02: Support & Operations — API Route

import { NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getComponentHealth } from '@/lib/monitoring/metrics'

export async function GET() {
  try {
    const [activeIncidents, recentResolved, components] = await Promise.all([
      db.incident.findMany({
        where: { status: { in: ['investigating', 'identified', 'monitoring'] } },
        include: { updates: { orderBy: { createdAt: 'desc' as const }, take: 5 } },
        orderBy: { startedAt: 'desc' },
      }),
      db.incident.findMany({
        where: {
          status: 'resolved',
          resolvedAt: { gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) },
        },
        orderBy: { resolvedAt: 'desc' },
        take: 5,
      }),
      getComponentHealth(),
    ])

    const allHealthy = components.every(c => c.healthy)
    const overallStatus = activeIncidents.length > 0
      ? 'degraded'
      : allHealthy ? 'operational' : 'partial'

    return NextResponse.json({
      status: overallStatus,
      components: components.map(c => ({
        name: c.name,
        status: c.healthy ? 'operational' : 'degraded',
        responseTime: c.responseTime,
        lastChecked: new Date().toISOString(),
      })),
      activeIncidents,
      recentResolved,
      uptime: 99.95, // Simulated — in production, calculated from SLATracking
      lastUpdated: new Date().toISOString(),
    })
  } catch (error) {
    console.error('[Status GET] Error:', error)
    return NextResponse.json({
      status: 'unknown',
      components: [],
      activeIncidents: [],
      recentResolved: [],
      uptime: 0,
      error: 'Failed to fetch status',
    }, { status: 500 })
  }
}
