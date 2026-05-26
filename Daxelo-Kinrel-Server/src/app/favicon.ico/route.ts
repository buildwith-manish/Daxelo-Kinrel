import { NextResponse } from 'next/server'

/**
 * Favicon Route — redirects /favicon.ico requests to the Kinrel SVG icon.
 *
 * Most modern browsers use the <link rel="icon"> from metadata,
 * but some legacy browsers and crawlers still request /favicon.ico directly.
 * This route ensures they get the correct icon.
 */
export function GET() {
  return NextResponse.redirect(
    new URL('/brand/icons/kinrel-icon-mini.svg', 'https://daxelokinrel.com'),
    302
  )
}
