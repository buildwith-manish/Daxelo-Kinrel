// DAXELO KINREL — Shareable Link Preview
// Pack 04: WhatsApp Platform — API Route
//
// GET /api/share/[token]
// Returns an HTML page with Open Graph meta tags for WhatsApp link preview.
// When opened in a browser, the page redirects to the deep link via HTTP refresh.
// When crawled by WhatsApp's link preview bot, it reads the OG meta tags instead.

import { db } from '@/lib/db'
import { trackInviteEvent } from '@/lib/invitations/conversion-tracking'

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ token: string }> }
) {
  try {
    const { token } = await params

    // Find the shareable link by token
    const shareableLink = await db.shareableLink.findUnique({
      where: { token },
    })

    if (!shareableLink) {
      return new Response(
        JSON.stringify({ error: 'Shareable link not found' }),
        {
          status: 404,
          headers: { 'Content-Type': 'application/json' },
        }
      )
    }

    // Check if link has expired
    if (shareableLink.expiresAt && shareableLink.expiresAt < new Date()) {
      return new Response(
        JSON.stringify({ error: 'This shareable link has expired' }),
        {
          status: 410,
          headers: { 'Content-Type': 'application/json' },
        }
      )
    }

    // Increment view count (fire-and-forget, don't block the response)
    db.shareableLink.update({
      where: { id: shareableLink.id },
      data: { viewCount: { increment: 1 } },
    }).catch((err) => {
      console.error('[Share GET] Failed to increment view count:', err)
    })

    // Track the link tap event (fire-and-forget)
    trackInviteEvent({
      event: 'invite:link_tapped',
      familyId: shareableLink.familyId ?? undefined,
      metadata: {
        shareToken: shareableLink.token,
        cardType: shareableLink.cardType,
      },
    }).catch((err) => {
      console.error('[Share GET] Failed to track link tap event:', err)
    })

    // Build the OG image URL pointing to the card endpoint
    const baseUrl = process.env.NEXT_PUBLIC_APP_URL || 'https://daxelo.app'
    const ogImageUrl = `${baseUrl}/api/share/${token}/card`

    // Build OG title and description based on card type
    const ogTitle = shareableLink.title
    const ogDescription = shareableLink.description

    // Generate HTML with OG meta tags for WhatsApp link preview
    // Uses HTTP refresh meta tag to redirect real browsers to the deep link
    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${escapeHtml(ogTitle)}</title>

  <!-- HTTP Refresh: Redirect real browsers to the deep link after 0 seconds -->
  <meta http-equiv="refresh" content="0;url=${escapeHtml(shareableLink.deepLinkUrl)}" />

  <!-- Open Graph Meta Tags for WhatsApp/Telegram/Facebook Preview -->
  <meta property="og:title" content="${escapeHtml(ogTitle)}" />
  <meta property="og:description" content="${escapeHtml(ogDescription)}" />
  <meta property="og:image" content="${escapeHtml(ogImageUrl)}" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:type" content="website" />
  <meta property="og:url" content="${escapeHtml(`${baseUrl}/api/share/${token}`)}" />
  <meta property="og:site_name" content="Daxelo Kinrel" />

  <!-- Twitter Card Meta Tags -->
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${escapeHtml(ogTitle)}" />
  <meta name="twitter:description" content="${escapeHtml(ogDescription)}" />
  <meta name="twitter:image" content="${escapeHtml(ogImageUrl)}" />

  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      margin: 0;
      background: #FFF7ED;
      color: #1C1917;
    }
    .container {
      text-align: center;
      padding: 2rem;
      max-width: 480px;
    }
    .spinner {
      width: 40px;
      height: 40px;
      border: 3px solid #F97316;
      border-top-color: transparent;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin: 0 auto 1.5rem;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
    h1 {
      font-size: 1.25rem;
      font-weight: 700;
      margin-bottom: 0.5rem;
    }
    p {
      font-size: 0.875rem;
      color: #57534E;
    }
    a {
      display: inline-block;
      margin-top: 1.5rem;
      padding: 0.75rem 1.5rem;
      background: #F97316;
      color: #FFFFFF;
      border-radius: 8px;
      text-decoration: none;
      font-weight: 600;
      font-size: 0.875rem;
    }
    a:hover {
      background: #EA580C;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="spinner"></div>
    <h1>Opening Daxelo Kinrel...</h1>
    <p>You're being redirected to the app. If nothing happens, tap the button below.</p>
    <a href="${escapeHtml(shareableLink.deepLinkUrl)}">Open in Daxelo Kinrel</a>
  </div>
</body>
</html>`

    return new Response(html, {
      status: 200,
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        Pragma: 'no-cache',
        Expires: '0',
      },
    })
  } catch (error) {
    console.error('[Share GET] Error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    )
  }
}

/**
 * Escapes HTML special characters to prevent XSS in the generated HTML page.
 */
function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
}
