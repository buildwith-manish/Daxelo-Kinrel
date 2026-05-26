// DAXELO KINREL — Pack 09: Family Events API
// GET — List family events  |  POST — Create event + auto-RSVP + auto-reminders + feed post

import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { getDefaultReminders } from '@/lib/community/event-types';
import { recordContribution } from '@/lib/community/contribution-tracker';

interface RouteContext {
  params: Promise<{ familyId: string }>;
}

// GET /api/v1/families/[familyId]/events
export async function GET(
  request: NextRequest,
  context: RouteContext
) {
  try {
    const { familyId } = await context.params;
    const { searchParams } = new URL(request.url);
    const upcoming = searchParams.get('upcoming') === 'true';
    const eventType = searchParams.get('eventType');
    const page = parseInt(searchParams.get('page') ?? '1');
    const limit = Math.min(parseInt(searchParams.get('limit') ?? '20'), 100);
    const skip = (page - 1) * limit;

    const where: Record<string, unknown> = {
      familyId,
      isCancelled: false,
    };

    if (upcoming) {
      where.startDate = { gte: new Date() };
    }

    if (eventType) {
      where.eventType = eventType;
    }

    const [events, total] = await Promise.all([
      db.communityEvent.findMany({
        where,
        skip,
        take: limit,
        orderBy: { startDate: 'asc' },
        include: {
          _count: { select: { rsvps: true, reminders: true } },
        },
      }),
      db.communityEvent.count({ where }),
    ]);

    return NextResponse.json({
      events,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    console.error('GET /api/v1/families/[familyId]/events error:', error);
    return NextResponse.json(
      { error: 'Failed to fetch events' },
      { status: 500 }
    );
  }
}

// POST /api/v1/families/[familyId]/events
export async function POST(
  request: NextRequest,
  context: RouteContext
) {
  try {
    const { familyId } = await context.params;
    const body = await request.json();
    const {
      creatorId,
      title,
      description,
      eventType,
      startDate,
      endDate,
      isAllDay,
      isRecurring,
      recurrenceRule,
      location,
      locationUrl,
      meetingUrl,
      visibility,
      coverImageUrl,
      communityId,
      metadata,
    } = body;

    if (!creatorId || !title || !startDate) {
      return NextResponse.json(
        { error: 'Missing required fields: creatorId, title, startDate' },
        { status: 400 }
      );
    }

    // Verify family exists and user is a member
    const familyMember = await db.familyMember.findFirst({
      where: { familyId, userId: creatorId },
    });

    if (!familyMember) {
      return NextResponse.json(
        { error: 'You must be a family member to create events' },
        { status: 403 }
      );
    }

    const resolvedEventType = eventType ?? 'custom';
    const resolvedVisibility = visibility ?? 'family';

    // Create event
    const event = await db.communityEvent.create({
      data: {
        familyId,
        communityId,
        creatorId,
        title,
        description,
        eventType: resolvedEventType,
        startDate: new Date(startDate),
        endDate: endDate ? new Date(endDate) : null,
        isAllDay: isAllDay ?? false,
        isRecurring: isRecurring ?? false,
        recurrenceRule,
        location,
        locationUrl,
        meetingUrl,
        visibility: resolvedVisibility,
        coverImageUrl,
        metadata: metadata ? JSON.stringify(metadata) : null,
      },
    });

    // Auto-RSVP the creator as attending
    await db.eventRSVP.create({
      data: {
        eventId: event.id,
        userId: creatorId,
        status: 'attending',
      },
    });

    // Auto-create reminders based on event type defaults
    const reminderOffsets = getDefaultReminders(resolvedEventType);
    for (const offsetMinutes of reminderOffsets) {
      const remindAt = new Date(new Date(startDate).getTime() - offsetMinutes * 60 * 1000);
      if (remindAt > new Date()) {
        await db.eventReminder.create({
          data: {
            eventId: event.id,
            userId: creatorId,
            remindAt,
          },
        });
      }
    }

    // Also create reminders for all other family members
    const familyMembers = await db.familyMember.findMany({
      where: { familyId, userId: { not: creatorId } },
      select: { userId: true },
    });

    for (const member of familyMembers) {
      // Auto-RSVP as pending
      await db.eventRSVP.create({
        data: {
          eventId: event.id,
          userId: member.userId,
          status: 'pending',
        },
      });

      // Create reminders
      for (const offsetMinutes of reminderOffsets) {
        const remindAt = new Date(new Date(startDate).getTime() - offsetMinutes * 60 * 1000);
        if (remindAt > new Date()) {
          await db.eventReminder.create({
            data: {
              eventId: event.id,
              userId: member.userId,
              remindAt,
            },
          });
        }
      }
    }

    // Create a feed post for the event
    await db.communityPost.create({
      data: {
        familyId,
        communityId,
        authorId: creatorId,
        type: 'event',
        title: `📅 ${title}`,
        body: description ?? `New event: ${title}`,
        visibility: resolvedVisibility === 'public' ? 'public' : 'family_only',
        metadata: JSON.stringify({ eventId: event.id, eventType: resolvedEventType }),
      },
    });

    // Record contribution
    await recordContribution(creatorId, familyId, 'eventCreated');

    return NextResponse.json({ event }, { status: 201 });
  } catch (error) {
    console.error('POST /api/v1/families/[familyId]/events error:', error);
    return NextResponse.json(
      { error: 'Failed to create event' },
      { status: 500 }
    );
  }
}
