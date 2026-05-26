// DAXELO KINREL — Admin KB Analytics API
// Pack 02: Support & Operations — API Route

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const days = parseInt(searchParams.get('days') ?? '30')

    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000)

    // Top articles by views
    const topArticles = await db.kBArticle.findMany({
      where: { status: 'published' },
      orderBy: { views: 'desc' },
      take: 20,
      select: {
        id: true,
        slug: true,
        title: true,
        views: true,
        helpfulYes: true,
        helpfulNo: true,
        category: true,
      },
    })

    // Failed searches (led to ticket)
    const failedSearchesRaw = await db.kBSearchLog.findMany({
      where: {
        ledToTicket: true,
        createdAt: { gte: since },
      },
      orderBy: { createdAt: 'desc' },
      take: 50,
      select: { query: true, language: true, createdAt: true },
    })

    // Aggregate failed searches by query
    const failedSearchCounts: Record<string, number> = {}
    for (const s of failedSearchesRaw) {
      const key = s.query.toLowerCase()
      failedSearchCounts[key] = (failedSearchCounts[key] ?? 0) + 1
    }
    const failedSearches = Object.entries(failedSearchCounts)
      .map(([query, count]) => ({ query, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 20)

    // Searches with no results (content gaps)
    const noResultSearches = await db.kBSearchLog.findMany({
      where: {
        resultsCount: 0,
        createdAt: { gte: since },
      },
      orderBy: { createdAt: 'desc' },
      take: 50,
      select: { query: true, language: true },
    })

    // Aggregate no-result searches
    const noResultCounts: Record<string, { query: string; count: number; languages: Set<string> }> = {}
    for (const s of noResultSearches) {
      const key = s.query.toLowerCase()
      if (!noResultCounts[key]) {
        noResultCounts[key] = { query: key, count: 0, languages: new Set() }
      }
      noResultCounts[key].count++
      noResultCounts[key].languages.add(s.language)
    }

    const contentGaps = Object.values(noResultCounts)
      .map(({ query, count, languages }) => ({ query, count, languages: Array.from(languages) }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 20)

    // Articles with low helpfulness
    const unhelpfulArticles = topArticles
      .filter(a => a.views > 50 && (a.helpfulYes + a.helpfulNo) > 0)
      .map(a => ({
        ...a,
        helpfulnessScore: Math.round((a.helpfulYes / (a.helpfulYes + a.helpfulNo)) * 100) / 100,
      }))
      .sort((a, b) => a.helpfulnessScore - b.helpfulnessScore)
      .slice(0, 10)

    // Parse localized titles
    const articlesWithTitles = topArticles.map(a => {
      let title = ''
      try {
        const t = JSON.parse(a.title as string)
        title = t['en'] || ''
      } catch {
        title = String(a.title)
      }
      return { ...a, title }
    })

    return NextResponse.json({
      days,
      topArticles: articlesWithTitles,
      failedSearches,
      contentGaps,
      unhelpfulArticles,
      totalSearches: await db.kBSearchLog.count({ where: { createdAt: { gte: since } } }),
      totalArticles: await db.kBArticle.count({ where: { status: 'published' } }),
    })
  } catch (error) {
    console.error('[KB Analytics GET] Error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
