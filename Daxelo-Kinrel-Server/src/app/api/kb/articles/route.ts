// DAXELO KINREL — Knowledge Base Articles API
// Pack 02: Support & Operations — API Route

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const category = searchParams.get('category')
    const lang = searchParams.get('lang') ?? 'en'
    const page = parseInt(searchParams.get('page') ?? '1')
    const limit = parseInt(searchParams.get('limit') ?? '20')
    const slug = searchParams.get('slug')

    // Single article by slug
    if (slug) {
      const article = await db.kBArticle.findUnique({ where: { slug } })
      if (!article || article.status !== 'published') {
        return NextResponse.json({ error: 'Article not found' }, { status: 404 })
      }

      // Increment views
      await db.kBArticle.update({
        where: { id: article.id },
        data: { views: { increment: 1 } },
      })

      // Parse localized content
      let title = '', content = '', excerpt = ''
      try {
        const t = JSON.parse(article.title as string)
        const c = JSON.parse(article.content as string)
        const e = JSON.parse(article.excerpt as string)
        title = t[lang] || t['en'] || ''
        content = c[lang] || c['en'] || ''
        excerpt = e[lang] || e['en'] || ''
      } catch {
        title = String(article.title)
        content = String(article.content)
        excerpt = String(article.excerpt)
      }

      let tags: string[] = []
      try { tags = JSON.parse(article.tags as string) } catch {}

      return NextResponse.json({
        article: {
          id: article.id,
          slug: article.slug,
          category: article.category,
          subcategory: article.subcategory,
          title,
          content,
          excerpt,
          tags,
          views: article.views + 1,
          helpfulYes: article.helpfulYes,
          helpfulNo: article.helpfulNo,
          publishedAt: article.publishedAt,
        },
      })
    }

    // List articles
    const where: Record<string, unknown> = { status: 'published' }
    if (category) where.category = category

    const [articles, total] = await Promise.all([
      db.kBArticle.findMany({
        where,
        orderBy: [{ featured: 'desc' }, { sortOrder: 'asc' }, { views: 'desc' }],
        skip: (page - 1) * limit,
        take: limit,
      }),
      db.kBArticle.count({ where }),
    ])

    const localizedArticles = articles.map(article => {
      let title = '', excerpt = ''
      try {
        const t = JSON.parse(article.title as string)
        const e = JSON.parse(article.excerpt as string)
        title = t[lang] || t['en'] || ''
        excerpt = e[lang] || e['en'] || ''
      } catch {
        title = String(article.title)
        excerpt = String(article.excerpt)
      }

      let tags: string[] = []
      try { tags = JSON.parse(article.tags as string) } catch {}

      return {
        id: article.id,
        slug: article.slug,
        category: article.category,
        subcategory: article.subcategory,
        title,
        excerpt,
        tags,
        featured: article.featured,
        views: article.views,
        helpfulYes: article.helpfulYes,
        helpfulNo: article.helpfulNo,
        publishedAt: article.publishedAt,
      }
    })

    return NextResponse.json({ articles: localizedArticles, total, page, limit })
  } catch (error) {
    console.error('[KB Articles GET] Error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}

// Helpful/Not helpful feedback
export async function PATCH(request: NextRequest) {
  try {
    const body = await request.json()
    const { slug, helpful } = body as { slug: string; helpful: boolean }

    if (!slug || typeof helpful !== 'boolean') {
      return NextResponse.json({ error: 'slug and helpful (boolean) required' }, { status: 400 })
    }

    const article = await db.kBArticle.findUnique({ where: { slug } })
    if (!article) {
      return NextResponse.json({ error: 'Article not found' }, { status: 404 })
    }

    await db.kBArticle.update({
      where: { slug },
      data: helpful ? { helpfulYes: { increment: 1 } } : { helpfulNo: { increment: 1 } },
    })

    return NextResponse.json({ success: true })
  } catch (error) {
    console.error('[KB Articles PATCH] Error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
