// DAXELO KINREL — Pack 10: Knowledge Base Articles API
// GET /api/kb — Search & list KB articles

import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'

export async function GET(request: NextRequest) {
  const session = await getServerSession(authOptions)
  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const url = new URL(request.url)
  const category = url.searchParams.get('category')
  const lang = url.searchParams.get('lang') || 'en'
  const search = url.searchParams.get('q') || ''
  const page = Math.max(1, parseInt(url.searchParams.get('page') || '1'))
  const limit = Math.min(50, Math.max(1, parseInt(url.searchParams.get('limit') || '20')))

  const where: Record<string, unknown> = {
    status: 'published',
  }

  if (category) {
    where.category = category
  }

  // Search: look in title/content JSON strings (basic text search)
  if (search) {
    where.OR = [
      { title: { contains: search } },
      { content: { contains: search } },
      { tags: { contains: search } },
    ]
  }

  const [articles, total] = await Promise.all([
    db.kBArticle.findMany({
      where,
      select: {
        id: true,
        slug: true,
        category: true,
        subcategory: true,
        title: true,
        excerpt: true,
        tags: true,
        featured: true,
        views: true,
        helpfulYes: true,
        helpfulNo: true,
        sortOrder: true,
        publishedAt: true,
        createdAt: true,
      },
      orderBy: [
        { featured: 'desc' },
        { sortOrder: 'asc' },
        { publishedAt: 'desc' },
      ],
      skip: (page - 1) * limit,
      take: limit,
    }),
    db.kBArticle.count({ where }),
  ])

  // Parse localized title/excerpt for the requested language
  const localizedArticles = articles.map((article) => {
    let titleStr = article.title
    let excerptStr = article.excerpt

    try {
      const titleJson = JSON.parse(article.title) as Record<string, string>
      titleStr = titleJson[lang] || titleJson['en'] || article.title
    } catch {
      // Keep original if not JSON
    }

    try {
      const excerptJson = JSON.parse(article.excerpt) as Record<string, string>
      excerptStr = excerptJson[lang] || excerptJson['en'] || article.excerpt
    } catch {
      // Keep original if not JSON
    }

    return {
      ...article,
      title: titleStr,
      excerpt: excerptStr,
    }
  })

  return NextResponse.json({
    articles: localizedArticles,
    pagination: {
      page,
      limit,
      total,
      hasMore: page * limit < total,
    },
  })
}
