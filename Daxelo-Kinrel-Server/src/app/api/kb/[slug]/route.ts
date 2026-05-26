// DAXELO KINREL — Pack 10: Single KB Article API
// GET /api/kb/:slug

import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ slug: string }> }
) {
  const session = await getServerSession(authOptions)
  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { slug } = await params
  const url = new URL(request.url)
  const lang = url.searchParams.get('lang') || 'en'

  const article = await db.kBArticle.findUnique({
    where: { slug },
    include: {
      author: {
        select: { id: true, name: true },
      },
      lastEditedBy: {
        select: { id: true, name: true },
      },
    },
  })

  if (!article) {
    return NextResponse.json({ error: 'Article not found' }, { status: 404 })
  }

  if (article.status !== 'published') {
    return NextResponse.json({ error: 'Article not found' }, { status: 404 })
  }

  // Increment views
  await db.kBArticle.update({
    where: { id: article.id },
    data: { views: { increment: 1 } },
  })

  // Parse localized fields
  let titleStr = article.title
  let contentStr = article.content
  let excerptStr = article.excerpt

  try {
    const titleJson = JSON.parse(article.title) as Record<string, string>
    titleStr = titleJson[lang] || titleJson['en'] || article.title
  } catch {
    // Keep original
  }

  try {
    const contentJson = JSON.parse(article.content) as Record<string, string>
    contentStr = contentJson[lang] || contentJson['en'] || article.content
  } catch {
    // Keep original
  }

  try {
    const excerptJson = JSON.parse(article.excerpt) as Record<string, string>
    excerptStr = excerptJson[lang] || excerptJson['en'] || article.excerpt
  } catch {
    // Keep original
  }

  // Parse tags and related articles
  let tags: string[] = []
  try {
    tags = JSON.parse(article.tags) as string[]
  } catch {
    // Keep empty
  }

  let relatedArticleIds: string[] = []
  try {
    relatedArticleIds = JSON.parse(article.relatedArticleIds) as string[]
  } catch {
    // Keep empty
  }

  return NextResponse.json({
    article: {
      id: article.id,
      slug: article.slug,
      category: article.category,
      subcategory: article.subcategory,
      title: titleStr,
      content: contentStr,
      excerpt: excerptStr,
      tags,
      relatedArticleIds,
      featured: article.featured,
      views: article.views + 1, // Show incremented value
      helpfulYes: article.helpfulYes,
      helpfulNo: article.helpfulNo,
      author: article.author,
      lastEditedBy: article.lastEditedBy,
      publishedAt: article.publishedAt,
      createdAt: article.createdAt,
      updatedAt: article.updatedAt,
    },
  })
}
