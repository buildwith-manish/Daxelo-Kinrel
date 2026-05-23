import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { apiMiddleware } from '@/lib/api/middleware'
import { success, error } from '@/lib/api/response'
import { apiVersionHeaders } from '@/lib/api/middleware'
import { getByGender } from '@/lib/kinship'

// ── GET /v1/families/:familyId/stats ─────────────────────────────────

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const { familyId } = await params
  const result = await apiMiddleware(request, {
    requiredScope: 'stats:read',
    endpoint: 'GET /v1/families/*/stats',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  // Check access
  const membership = await db.familyMember.findFirst({
    where: { familyId, userId: apiKey.userId },
  })

  if (!membership) {
    return error('NOT_FOUND', 'Family not found or access denied', 404)
  }

  // Get all persons for this family
  const persons = await db.person.findMany({
    where: { familyId },
    select: {
      id: true,
      isDeceased: true,
      dateOfBirth: true,
      relationship: true,
    },
  })

  // Get relationships
  const relationships = await db.relationship.findMany({
    where: { familyId },
    select: { type: true },
  })

  // Calculate statistics
  const totalCount = persons.length
  const livingCount = persons.filter(p => !p.isDeceased).length
  const deceasedCount = persons.filter(p => p.isDeceased).length

  // Gender distribution — powered by kinship module (523 terms with gender metadata)
  const maleKeys = new Set(getByGender('male').map(r => r.relationshipKey))
  const femaleKeys = new Set(getByGender('female').map(r => r.relationshipKey))

  const genderDistribution: Record<string, number> = { male: 0, female: 0, unknown: 0 }
  for (const person of persons) {
    if (person.relationship) {
      const rel = person.relationship.toLowerCase()
      if (maleKeys.has(rel)) {
        genderDistribution.male++
      } else if (femaleKeys.has(rel)) {
        genderDistribution.female++
      } else {
        genderDistribution.unknown++
      }
    } else {
      genderDistribution.unknown++
    }
  }

  // Average age (for living persons with DOB)
  const now = new Date()
  const livingWithDOB = persons.filter(p => !p.isDeceased && p.dateOfBirth)
  let avgAge = 0
  if (livingWithDOB.length > 0) {
    const totalAge = livingWithDOB.reduce((acc, p) => {
      const dob = p.dateOfBirth!
      const age = (now.getTime() - dob.getTime()) / (365.25 * 24 * 60 * 60 * 1000)
      return acc + age
    }, 0)
    avgAge = Math.round(totalAge / livingWithDOB.length * 10) / 10
  }

  // Generation range (approximate from ages)
  const generationRange = avgAge > 0 ? {
    youngest: Math.max(0, Math.round(avgAge - 30)),
    oldest: Math.round(avgAge + 30),
  } : null

  // Top relationship types
  const relationshipCounts: Record<string, number> = {}
  for (const person of persons) {
    if (person.relationship) {
      relationshipCounts[person.relationship] = (relationshipCounts[person.relationship] || 0) + 1
    }
  }
  const topRelationshipTypes = Object.entries(relationshipCounts)
    .sort(([, a], [, b]) => b - a)
    .slice(0, 10)
    .map(([type, count]) => ({ type, count }))

  // Top relationship types from Relationship model
  const relTypeCounts: Record<string, number> = {}
  for (const rel of relationships) {
    relTypeCounts[rel.type] = (relTypeCounts[rel.type] || 0) + 1
  }
  const topRelTypes = Object.entries(relTypeCounts)
    .sort(([, a], [, b]) => b - a)
    .slice(0, 10)
    .map(([type, count]) => ({ type, count }))

  const stats = {
    totalPersons: totalCount,
    livingCount,
    deceasedCount,
    genderDistribution,
    generationRange,
    averageAge: avgAge,
    topRelationshipTypes: topRelTypes.length > 0 ? topRelTypes : topRelationshipTypes,
    totalRelationships: relationships.length,
    memberCount: await db.familyMember.count({ where: { familyId } }),
  }

  const response = success(stats)

  return new NextResponse(response.body, {
    status: response.status,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}
