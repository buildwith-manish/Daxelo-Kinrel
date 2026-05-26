// DAXELO KINREL — Pack 09: Event RSVP API
// POST — Update RSVP status

import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';

interface RouteContext {
  params: Promise<{ eventId: string }>;
}

const VALID_RSVP_STATUSES = ['pending', 'attending', 'maybe', 'declined'];

// POST /api/v1/events/[eventId]/rsvp
export async function POST(
  request: NextRequest,
  context: RouteContext
) {
  try {
    const { eventId } = await context.params;
    const body = await request.json();
    const { userId, status, plusOne, note } = body;

    if (!userId || !status) {
      return NextResponse.json(
        { error: 'userId and status are required' },
        { status: 400 }
      );
    }

    if (!VALID_RSVP_STATUSES.includes(status)) {
      return NextResponse.json(
        { error: `Invalid RSVP status. Must be one of: ${VALID_RSVP_STATUSES.join(', ')}` },
        { status: 400 }
      );
    }

    // Verify event exists
    const event = await db.communityEvent.findUnique({
      where: { id: eventId },
    });

    if (!event) {
      return NextResponse.json({ error: 'Event not found' }, { status: 404 });
    }

    if (event.isCancelled) {
      return NextResponse.json(
        { error: 'Cannot RSVP to a cancelled event' },
        { status: 400 }
      );
    }

    // Upsert the RSVP
    const existingRSVP = await db.eventRSVP.findUnique({
      where: { eventId_userId: { eventId, userId } },
    });

    let rsvp;
    if (existingRSVP) {
      rsvp = await db.eventRSVP.update({
        where: { id: existingRSVP.id },
        data: {
          status,
          plusOne: plusOne ?? existingRSVP.plusOne,
          note: note ?? existingRSVP.note,
          respondedAt: new Date(),
        },
      });
    } else {
      rsvp = await db.eventRSVP.create({
        data: {
          eventId,
          userId,
          status,
          plusOne: plusOne ?? false,
          note,
          respondedAt: new Date(),
        },
      });
    }

    // Get updated RSVP summary
    const rsvpSummary = await db.eventRSVP.groupBy({
      by: ['status'],
      where: { eventId },
      _count: { status: true },
    });

    const summary: Record<string, number> = {
      pending: 0,
      attending: 0,
      maybe: 0,
      declined: 0,
    };
    for (const row of rsvpSummary) {
      summary[row.status] = row._count.status;
    }

    return NextResponse.json({ rsvp, summary });
  } catch (error) {
    console.error('POST /api/v1/events/[eventId]/rsvp error:', error);
    return NextResponse.json(
      { error: 'Failed to update RSVP' },
      { status: 500 }
    );
  }
}
