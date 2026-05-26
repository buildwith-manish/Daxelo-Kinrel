const http = require('http');
const fs = require('fs');
const path = require('path');

const FLUTTER_WEB = '/home/z/my-project/flutter_app/build/web';
const NEXT_BUILD = '/home/z/my-project/.next';
const PUBLIC_DIR = '/home/z/my-project/public';
const PORT = 3000;

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2',
  '.json': 'application/json',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.wasm': 'application/wasm',
  '.frag': 'text/plain',
  '.bin': 'application/octet-stream',
  '.symbols': 'application/octet-stream',
};

function getContentType(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return MIME_TYPES[ext] || 'application/octet-stream';
}

const server = http.createServer((req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    let pathname = url.pathname;

    // Root → Flutter index.html
    if (pathname === '/' || pathname === '') {
      serveFile(path.join(FLUTTER_WEB, 'index.html'), res);
      return;
    }

    // _next paths → Next.js build
    if (pathname.startsWith('/_next/')) {
      serveFile(path.join(NEXT_BUILD, pathname.slice(6)), res);
      return;
    }

    // Try Flutter build first
    const flutterPath = path.join(FLUTTER_WEB, pathname);
    if (fs.existsSync(flutterPath) && fs.statSync(flutterPath).isFile()) {
      serveFile(flutterPath, res);
      return;
    }

    // Try public directory
    const publicPath = path.join(PUBLIC_DIR, pathname);
    if (fs.existsSync(publicPath) && fs.statSync(publicPath).isFile()) {
      serveFile(publicPath, res);
      return;
    }

    // SPA fallback → Flutter index.html
    const indexPath = path.join(FLUTTER_WEB, 'index.html');
    if (fs.existsSync(indexPath)) {
      serveFile(indexPath, res);
      return;
    }

    res.writeHead(404);
    res.end('Not Found');
  } catch (err) {
    res.writeHead(500);
    res.end('Internal Server Error');
  }
});

function serveFile(filePath, res) {
  const resolved = path.resolve(filePath);
  
  fs.readFile(resolved, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('Not Found');
      return;
    }
    res.writeHead(200, {
      'Content-Type': getContentType(resolved),
      'Content-Length': data.length,
    });
    res.end(data);
  });
}

// Try IPv6 dual-stack first, then IPv4
server.listen(PORT, '::', () => {
  console.log(`KINREL Server on [::]:${PORT} (IPv4+IPv6)`);
  console.log(`Flutter app: ${FLUTTER_WEB}`);
}).on('error', () => {
  server.listen(PORT, '0.0.0.0', () => {
    console.log(`KINREL Server on 0.0.0.0:${PORT} (IPv4 only)`);
    console.log(`Flutter app: ${FLUTTER_WEB}`);
  });
});
