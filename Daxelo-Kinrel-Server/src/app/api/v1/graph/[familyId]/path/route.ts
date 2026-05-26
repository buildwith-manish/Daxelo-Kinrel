import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { apiMiddleware } from '@/lib/api/middleware'
import { success, error } from '@/lib/api/response'
import { findPath } from '@/lib/api/graph-traversal'
import { apiVersionHeaders } from '@/lib/api/middleware'

// ── GET /v1/graph/:familyId/path ─────────────────────────────────────

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const { familyId } = await params
  const result = await apiMiddleware(request, {
    requiredScope: 'graph:read',
    endpoint: 'GET /v1/graph/*/path',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result
  const url = new URL(request.url)

  // Check access
  const membership = await db.familyMember.findFirst({
    where: { familyId, userId: apiKey.userId },
  })

  if (!membership) {
    return error('NOT_FOUND', 'Family not found or access denied', 404)
  }

  // Required params
  const fromPersonId = url.searchParams.get('from')
  const toPersonId = url.searchParams.get('to')

  if (!fromPersonId || !toPersonId) {
    return error('MISSING_REQUIRED_FIELD', 'Both "from" and "to" person IDs are required', 400, {
      required: ['from', 'to'],
    })
  }

  // Verify both persons exist in this family
  const [fromPerson, toPerson] = await Promise.all([
    db.person.findFirst({ where: { id: fromPersonId, familyId } }),
    db.person.findFirst({ where: { id: toPersonId, familyId } }),
  ])

  if (!fromPerson) {
    return error('NOT_FOUND', `Person "${fromPersonId}" not found in this family`, 404)
  }

  if (!toPerson) {
    return error('NOT_FOUND', `Person "${toPersonId}" not found in this family`, 404)
  }

  try {
    const pathResult = await findPath(familyId, fromPersonId, toPersonId)

    if (!pathResult) {
      const response = success({
        from: { id: fromPersonId, name: fromPerson.name },
        to: { id: toPersonId, name: toPerson.name },
        path: null,
        length: -1,
        message: 'No path found between these persons',
      })

      return new NextResponse(response.body, {
        status: response.status,
        headers: {
          ...Object.fromEntries(response.headers.entries()),
          ...rateLimitHeaders,
          ...apiVersionHeaders('1.0.0'),
        },
      })
    }

    // Enrich path steps with person names
    const enrichedPath = await Promise.all(
      pathResult.path.map(async (step) => {
        const rel = await db.relationship.findUnique({
          where: { id: step.relationshipId },
          include: {
            fromPerson: { select: { id: true, name: true } },
            toPerson: { select: { id: true, name: true } },
          },
        })

        return {
          ...step,
          fromPerson: rel?.fromPerson || { id: '', name: 'Unknown' },
          toPerson: rel?.toPerson || { id: '', name: 'Unknown' },
        }
      })
    )

    const response = success({
      from: { id: fromPersonId, name: fromPerson.name },
      to: { id: toPersonId, name: toPerson.name },
      path: enrichedPath,
      length: pathResult.length,
      relationshipDescription: pathResult.relationshipDescription,
      localizedDescription: pathResult.localizedDescription,
    })

    return new NextResponse(response.body, {
      status: response.status,
      headers: {
        ...Object.fromEntries(response.headers.entries()),
        ...rateLimitHeaders,
        ...apiVersionHeaders('1.0.0'),
      },
    })
  } catch {
    return error('INTERNAL_ERROR', 'Failed to find path', 500)
  }
}
