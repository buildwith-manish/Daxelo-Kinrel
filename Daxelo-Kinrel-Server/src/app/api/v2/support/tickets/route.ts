import { NextRequest } from 'next/server';
import { db } from '@/lib/db';
import { z } from 'zod';
import { success, created, error, collection } from '@/packages/api';

const createTicketSchema = z.object({
  userId: z.string().min(1),
  category: z.enum(['billing', 'account', 'data_loss', 'bug', 'feature_request', 'general', 'matrimonial', 'verification', 'privacy']),
  severity: z.enum(['critical', 'high', 'medium', 'low']).default('medium'),
  subject: z.string().min(5).max(255),
  description: z.string().min(10),
});

export async function POST(request: NextRequest) {
  try {
    const body = await request.json().catch(() => null);
    if (!body) return error('INVALID_PARAMETER', 'Invalid JSON body', 400);

    const parsed = createTicketSchema.safeParse(body);
    if (!parsed.success) return error('VALIDATION_ERROR', 'Validation failed', 400, parsed.error.issues.map(i => ({ path: i.path.join('.'), message: i.message })));

    const data = parsed.data;
    const ticketNumber = `DK-${new Date().getFullYear()}-${String(Date.now()).slice(-5)}`;

    const ticket = await db.supportTicket.create({
      data: {
        ticketNumber,
        userId: data.userId,
        category: data.category,
        severity: data.severity,
        subject: data.subject,
        description: data.description,
        attachments: '[]',
        slaTier: 'basic',
        language: 'en',
      },
    });

    return created({ ticket: { id: ticket.id, ticketNumber: ticket.ticketNumber, status: ticket.status, category: ticket.category, severity: ticket.severity, createdAt: ticket.createdAt } });
  } catch (err) {
    console.error('[Tickets POST] Error:', err);
    return error('INTERNAL_ERROR', 'Failed to create ticket', 500);
  }
}

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const status = searchParams.get('status');
    const page = parseInt(searchParams.get('page') ?? '1');
    const limit = Math.min(parseInt(searchParams.get('limit') ?? '20'), 100);

    const where: any = {};
    if (status) where.status = status;

    const [tickets, total] = await Promise.all([
      db.supportTicket.findMany({ where, orderBy: { createdAt: 'desc' }, skip: (page - 1) * limit, take: limit }),
      db.supportTicket.count({ where }),
    ]);

    return collection(tickets, { page, limit, total, hasMore: page * limit < total });
  } catch (err) {
    console.error('[Tickets GET] Error:', err);
    return error('INTERNAL_ERROR', 'Failed to fetch tickets', 500);
  }
}
