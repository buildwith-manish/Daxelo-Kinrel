// DAXELO KINREL — Graph API (Unified)
// GET /api/v1/graph/:familyId
// Supports both session cookie auth and Bearer API key auth
// If `from` and `to` query params present → findPath
// Otherwise → buildTree with optional `root` and `depth`

import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'
import { apiMiddleware } from '@/lib/api/middleware'
import { success, error } from '@/lib/api/response'
import { apiVersionHeaders } from '@/lib/api/middleware'
import { buildTree, findPath } from '@/lib/api/graph-traversal'
import { getKinshipTermByLocale, type LocaleCode } from '@/lib/kinship'

// ── Auth helper: session cookie OR Bearer API key ────────────────────

async function authenticate(request: NextRequest): Promise<{ userId: string; rateLimitHeaders?: Record<string, string> } | NextResponse> {
  // Try session cookie first
  const session = await getServerSession(authOptions)
  if (session?.user?.id) {
    return { userId: session.user.id }
  }

  // Fall back to Bearer API key
  const result = await apiMiddleware(request, {
    requiredScope: 'graph:read',
    endpoint: 'GET /v1/graph/*',
  })

  if (result instanceof NextResponse) return result

  return {
    userId: result.apiKey.userId,
    rateLimitHeaders: result.rateLimitHeaders,
  }
}

// ── GET ──────────────────────────────────────────────────────────────

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const { familyId } = await params
  const authResult = await authenticate(request)
  if (authResult instanceof NextResponse) return authResult

  const { userId, rateLimitHeaders } = authResult
  const url = new URL(request.url)

  // Check family access
  const membership = await db.familyMember.findFirst({
    where: { familyId, userId },
  })

  if (!membership) {
    return error('NOT_FOUND', 'Family not found or access denied', 404)
  }

  const locale = (url.searchParams.get('locale') || 'en') as LocaleCode

  // ── Path mode: from + to query params ──────────────────────────────
  const fromPersonId = url.searchParams.get('from')
  const toPersonId = url.searchParams.get('to')

  if (fromPersonId && toPersonId) {
    // Verify persons exist
    const [fromPerson, toPerson] = await Promise.all([
      db.person.findFirst({ where: { id: fromPersonId, familyId, deletedAt: null } }),
      db.person.findFirst({ where: { id: toPersonId, familyId, deletedAt: null } }),
    ])

    if (!fromPerson) {
      return error('NOT_FOUND', `Person "${fromPersonId}" not found`, 404)
    }
    if (!toPerson) {
      return error('NOT_FOUND', `Person "${toPersonId}" not found`, 404)
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
            ...(rateLimitHeaders || {}),
            ...apiVersionHeaders('1.0.0'),
          },
        })
      }

      // Get localized description
      const localizedDesc = locale !== 'en'
        ? getKinshipTermByLocale(pathResult.relationshipDescription, locale)
        : pathResult.relationshipDescription

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

          const localType = locale !== 'en'
            ? getKinshipTermByLocale(step.type, locale)
            : step.type

          return {
            ...step,
            localizedType: localType,
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
        localizedDescription: localizedDesc || pathResult.localizedDescription,
        locale,
      })

      return new NextResponse(response.body, {
        status: response.status,
        headers: {
          ...Object.fromEntries(response.headers.entries()),
          ...(rateLimitHeaders || {}),
          ...apiVersionHeaders('1.0.0'),
        },
      })
    } catch {
      return error('INTERNAL_ERROR', 'Failed to find path', 500)
    }
  }

  // ── Tree mode: root + depth query params ───────────────────────────
  const depth = Math.min(10, Math.max(1, parseInt(url.searchParams.get('depth') || '5')))
  const rootPersonId = url.searchParams.get('root')
  const format = url.searchParams.get('format') || 'nested'

  try {
    const tree = await buildTree(familyId, depth)

    // If root is specified, find that node in the tree
    let resultTree = tree
    if (rootPersonId) {
      const rootNode = findNodeInTree(tree, rootPersonId)
      if (rootNode) {
        resultTree = rootNode
      }
    }

    // Localize relationship labels if non-English locale
    if (locale !== 'en') {
      resultTree = localizeTree(resultTree, locale)
    }

    // Format: flat
    if (format === 'flat') {
      const flat: Array<Record<string, unknown>> = []

      function flatten(node: typeof resultTree, currentDepth: number, parentIds: string[] = []): void {
        flat.push({
          id: node.person.id,
          name: node.person.name,
          relationship: node.person.relationship,
          isDeceased: node.person.isDeceased,
          spouseId: node.spouse?.id,
          parentIds,
          depth: currentDepth,
        })
        for (const child of node.children) {
          flatten(child, currentDepth + 1, [node.person.id, ...(node.spouse ? [node.spouse.id] : [])])
        }
      }

      flatten(resultTree, 0)

      const response = success({
        familyId,
        format: 'flat',
        depth,
        locale,
        nodes: flat,
        totalNodes: flat.length,
      })

      return new NextResponse(response.body, {
        status: response.status,
        headers: {
          ...Object.fromEntries(response.headers.entries()),
          ...(rateLimitHeaders || {}),
          ...apiVersionHeaders('1.0.0'),
        },
      })
    }

    // Default: nested
    const response = success({
      familyId,
      format: 'nested',
      depth,
      locale,
      tree: resultTree,
    })

    return new NextResponse(response.body, {
      status: response.status,
      headers: {
        ...Object.fromEntries(response.headers.entries()),
        ...(rateLimitHeaders || {}),
        ...apiVersionHeaders('1.0.0'),
      },
    })
  } catch (err) {
    if (err instanceof Error && err.message === 'Family not found') {
      return error('NOT_FOUND', 'Family not found', 404)
    }
    return error('INTERNAL_ERROR', 'Failed to build family tree', 500)
  }
}

// ── Helpers ──────────────────────────────────────────────────────────

function findNodeInTree(node: { person: { id: string }; children: Array<{ person: { id: string }; children: unknown[] }> }, targetId: string): typeof node | null {
  if (node.person.id === targetId) return node
  for (const child of node.children) {
    const found = findNodeInTree(child as typeof node, targetId)
    if (found) return found
  }
  return null
}

function localizeTree(node: { person: { id: string; name: string; relationship: string | null; dateOfBirth: Date | null; isDeceased: boolean; privacyLevel: string; occupation: string | null; city: string | null; gotra: string | null }; spouse?: { id: string; name: string; relationship: string | null; dateOfBirth: Date | null; isDeceased: boolean; privacyLevel: string; occupation: string | null; city: string | null; gotra: string | null } | undefined; children: unknown[] }, locale: LocaleCode): typeof node {
  return {
    ...node,
    person: {
      ...node.person,
      relationship: node.person.relationship
        ? getKinshipTermByLocale(node.person.relationship, locale)
        : null,
    },
    spouse: node.spouse
      ? {
          ...node.spouse,
          relationship: node.spouse.relationship
            ? getKinshipTermByLocale(node.spouse.relationship, locale)
            : null,
        }
      : undefined,
    children: (node.children as Array<typeof node>).map((child) => localizeTree(child, locale)),
  }
}
