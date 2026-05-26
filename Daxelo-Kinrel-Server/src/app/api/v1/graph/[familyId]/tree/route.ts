import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { apiMiddleware } from '@/lib/api/middleware'
import { success, error } from '@/lib/api/response'
import { buildTree } from '@/lib/api/graph-traversal'
import { apiVersionHeaders } from '@/lib/api/middleware'

// ── GET /v1/graph/:familyId/tree ─────────────────────────────────────

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const { familyId } = await params
  const result = await apiMiddleware(request, {
    requiredScope: 'graph:read',
    endpoint: 'GET /v1/graph/*/tree',
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

  // Parse query params
  const depth = Math.min(10, Math.max(1, parseInt(url.searchParams.get('depth') || '5')))
  const includeDeceased = url.searchParams.get('includeDeceased') !== 'false'
  const format = url.searchParams.get('format') || 'nested' // nested | flat

  try {
    const tree = await buildTree(familyId, depth)

    // Filter deceased if requested
    function filterDeceased(node: typeof tree): typeof tree | null {
      if (!includeDeceased && node.person.isDeceased && node.children.length === 0) {
        return null
      }

      return {
        ...node,
        spouse: node.spouse && (!includeDeceased && node.spouse.isDeceased)
          ? undefined
          : node.spouse,
        children: node.children
          .map(child => filterDeceased(child))
          .filter((child): child is typeof tree => child !== null),
      }
    }

    const filteredTree = includeDeceased ? tree : (filterDeceased(tree) || tree)

    // Format: flat representation
    if (format === 'flat') {
      const flat: Array<{
        id: string
        name: string
        relationship: string | null
        isDeceased: boolean
        spouseId?: string
        parentIds: string[]
        depth: number
      }> = []

      function flatten(node: typeof tree, currentDepth: number, parentIds: string[] = []): void {
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

      flatten(filteredTree, 0)

      const response = success({
        familyId,
        format: 'flat',
        depth,
        nodes: flat,
        totalNodes: flat.length,
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

    // Default: nested format
    const response = success({
      familyId,
      format: 'nested',
      depth,
      tree: filteredTree,
    })

    return new NextResponse(response.body, {
      status: response.status,
      headers: {
        ...Object.fromEntries(response.headers.entries()),
        ...rateLimitHeaders,
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
