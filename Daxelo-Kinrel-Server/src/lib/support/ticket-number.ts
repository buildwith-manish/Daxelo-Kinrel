// DAXELO KINREL — Ticket & Incident Number Generator
// Pack 02: Support & Operations

import { db } from '@/lib/db'

export async function generateTicketNumber(): Promise<string> {
  const year = new Date().getFullYear()
  const count = await db.supportTicket.count()
  return `DK-${year}-${String(count + 1).padStart(5, '0')}`
}

export async function generateIncidentNumber(): Promise<string> {
  const year = new Date().getFullYear()
  const count = await db.incident.count()
  return `INC-${year}-${String(count + 1).padStart(5, '0')}`
}
