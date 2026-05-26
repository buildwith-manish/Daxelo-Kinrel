// ── Combined Static + API Proxy Server ─────────────────────────────────────
// Serves the built Next.js page AND proxies /api/kinship/* to the mini-service

const KINSHIP_SERVICE = 'http://127.0.0.1:3002';
const PROJECT = '/home/z/my-project';

const server = Bun.serve({
  port: 3000,
  async fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;

    // Proxy /api/kinship/* to the mini-service
    if (path.startsWith('/api/kinship')) {
      try {
        const upstreamUrl = `${KINSHIP_SERVICE}${path}${url.search}`;
        const upstreamRes = await fetch(upstreamUrl, {
          method: req.method,
          headers: req.headers,
          body: req.body,
        });
        const body = await upstreamRes.text();
        return new Response(body, {
          status: upstreamRes.status,
          headers: upstreamRes.headers,
        });
      } catch {
        return new Response(JSON.stringify({ error: 'Kinship service unavailable' }), {
          status: 503,
          headers: { 'Content-Type': 'application/json' },
        });
      }
    }

    // Serve the homepage
    if (path === '/' || path === '') {
      return new Response(Bun.file(`${PROJECT}/.next/server/app/index.html`), {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    }

    // Serve static assets
    let fp;
    if (path.startsWith('/_next/')) {
      fp = `${PROJECT}/.next${path.substring(6)}`;
    } else {
      fp = `${PROJECT}/public${path}`;
    }

    const f = Bun.file(fp);
    if (f.size > 0) return new Response(f);
    return new Response('Not found', { status: 404 });
  },
});

console.log(`KINREL on :${server.port} (static + API proxy)`);
