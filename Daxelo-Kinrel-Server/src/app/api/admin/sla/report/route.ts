// DAXELO KINREL — Admin SLA Report API
// Pack 02: Support & Operations — API Route

import { NextRequest, NextResponse } from 'next/server'
import { getSLAReport } from '@/lib/support/sla-credits'

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const month = searchParams.get('month') ?? new Date().toISOString().slice(0, 7) // YYYY-MM

    const report = await getSLAReport(month)

    return NextResponse.json(report)
  } catch (error) {
    console.error('[SLA Report GET] Error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
