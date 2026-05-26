import { NextRequest, NextResponse } from 'next/server';
import { readFile } from 'fs/promises';
import { join, extname } from 'path';

const FLUTTER_WEB_ROOT = join(process.cwd(), 'flutter_app', 'build', 'web');

const MIME_TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.woff2': 'font/woff2',
  '.wasm': 'application/wasm',
  '.otf': 'font/otf',
  '.ico': 'image/x-icon',
  '.frag': 'text/plain',
  '.bin': 'application/octet-stream',
  '.symbols': 'application/octet-stream',
};

function getMimeType(filePath: string): string {
  const ext = extname(filePath).toLowerCase();
  return MIME_TYPES[ext] || 'application/octet-stream';
}

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ path?: string[] }> }
) {
  const { path: pathSegments } = await params;
  const filePath = pathSegments ? pathSegments.join('/') : 'index.html';
  const fullPath = join(FLUTTER_WEB_ROOT, filePath);

  if (!fullPath.startsWith(FLUTTER_WEB_ROOT)) {
    return new NextResponse('Forbidden', { status: 403 });
  }

  try {
    const data = await readFile(fullPath);
    const contentType = getMimeType(fullPath);
    return new NextResponse(data, {
      headers: {
        'Content-Type': contentType,
        'Cache-Control': 'public, max-age=31536000, immutable',
      },
    });
  } catch {
    try {
      const indexData = await readFile(join(FLUTTER_WEB_ROOT, 'index.html'));
      return new NextResponse(indexData, {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    } catch {
      return new NextResponse('Not Found', { status: 404 });
    }
  }
}
