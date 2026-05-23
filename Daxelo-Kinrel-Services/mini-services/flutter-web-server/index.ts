import { resolve, extname, join } from "path";

const WEB_ROOT = resolve(import.meta.dir, "../../flutter_app/build/web");
const PORT = 3000;

const MIME_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ttf": "font/ttf",
  ".woff2": "font/woff2",
  ".wasm": "application/wasm",
  ".otf": "font/otf",
  ".ico": "image/x-icon",
  ".frag": "text/plain",
  ".bin": "application/octet-stream",
  ".symbols": "application/octet-stream",
};

function getMimeType(filePath: string): string {
  const ext = extname(filePath).toLowerCase();
  return MIME_TYPES[ext] || "application/octet-stream";
}

const server = Bun.serve({
  port: PORT,
  hostname: "0.0.0.0",
  fetch(req) {
    const url = new URL(req.url);
    let pathname = url.pathname;

    // Normalize: remove trailing slash except for root
    if (pathname !== "/" && pathname.endsWith("/")) {
      pathname = pathname.slice(0, -1);
    }

    // Root path → index.html
    if (pathname === "/") {
      const file = Bun.file(join(WEB_ROOT, "index.html"));
      return new Response(file, {
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    }

    // Try to serve the exact file
    const filePath = join(WEB_ROOT, pathname);
    const file = Bun.file(filePath);
    const contentType = getMimeType(filePath);
    return new Response(file, {
      headers: { "Content-Type": contentType },
    });
  },
});

console.log(`🧡 KINREL Flutter Web Server running on http://0.0.0.0:${PORT}`);
console.log(`📁 Serving static files from: ${WEB_ROOT}`);
