// DAXELO KINREL — Knowledge Base Search API
// Pack 02: Support & Operations — API Route

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { z } from 'zod'

const searchSchema = z.object({
  q: z.string().min(2).max(200),
  lang: z.string().length(2).default('en'),
  category: z.string().optional(),
  limit: z.coerce.number().min(1).max(20).default(10),
})

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const parsed = searchSchema.safeParse({
      q: searchParams.get('q'),
      lang: searchParams.get('lang') ?? 'en',
      category: searchParams.get('category') ?? undefined,
      limit: searchParams.get('limit') ?? '10',
    })

    if (!parsed.success) {
      return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 })
    }

    const { q, lang, category, limit } = parsed.data

    // SQLite-compatible search using LIKE
    // For localized content, parse JSON and search
    const where: Record<string, unknown> = { status: 'published' }
    if (category) where.category = category

    const allArticles = await db.kBArticle.findMany({
      where,
      orderBy: { views: 'desc' },
    })

    // Filter articles by search term in localized title/content
    const searchTerm = q.toLowerCase()
    const results = allArticles
      .map(article => {
        let title = ''
        let excerpt = ''
        let content = ''

        try {
          const titleObj = JSON.parse(article.title as string)
          const excerptObj = JSON.parse(article.excerpt as string)
          const contentObj = JSON.parse(article.content as string)
          title = titleObj[lang] || titleObj['en'] || ''
          excerpt = excerptObj[lang] || excerptObj['en'] || ''
          content = contentObj[lang] || contentObj['en'] || ''
        } catch {
          title = String(article.title)
          excerpt = String(article.excerpt)
          content = String(article.content)
        }

        // Calculate simple relevance score
        const titleMatch = title.toLowerCase().includes(searchTerm) ? 10 : 0
        const excerptMatch = excerpt.toLowerCase().includes(searchTerm) ? 5 : 0
        const contentMatch = content.toLowerCase().includes(searchTerm) ? 2 : 0
        const tagMatch = (() => {
          try {
            const tags: string[] = JSON.parse(article.tags as string)
            return tags.some(t => t.toLowerCase().includes(searchTerm)) ? 3 : 0
          } catch { return 0 }
        })()

        const rank = titleMatch + excerptMatch + contentMatch + tagMatch

        return { id: article.id, slug: article.slug, category: article.category, title, excerpt, rank }
      })
      .filter(r => r.rank > 0)
      .sort((a, b) => b.rank - a.rank)
      .slice(0, limit)

    // Log search
    await db.kBSearchLog.create({
      data: {
        query: q,
        language: lang,
        resultsCount: results.length,
      },
    })

    // Update search appearances
    if (results.length > 0) {
      await db.kBArticle.updateMany({
        where: { id: { in: results.map(r => r.id) } },
        data: { searchAppearances: { increment: 1 } },
      })
    }

    return NextResponse.json({ results, query: q, language: lang })
  } catch (error) {
    console.error('[KB Search GET] Error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
