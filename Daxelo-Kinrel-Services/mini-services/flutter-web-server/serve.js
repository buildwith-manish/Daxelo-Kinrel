const http = require('http');
const fs = require('fs');
const path = require('path');

const WEB_ROOT = path.resolve(__dirname, '../../flutter_app/build/web');
const PORT = 3000;

const MIME_TYPES = {
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
};

function getMimeType(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return MIME_TYPES[ext] || 'application/octet-stream';
}

const server = http.createServer((req, res) => {
  let pathname = new URL(req.url, 'http://localhost').pathname;
  
  if (pathname !== '/' && pathname.endsWith('/')) {
    pathname = pathname.slice(0, -1);
  }

  if (pathname === '/') {
    pathname = '/index.html';
  }

  const filePath = path.join(WEB_ROOT, pathname);
  
  if (!filePath.startsWith(WEB_ROOT)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  fs.readFile(filePath, (err, data) => {
    if (err) {
      const indexPath = path.join(WEB_ROOT, 'index.html');
      fs.readFile(indexPath, (err2, indexData) => {
        if (err2) {
          res.writeHead(404);
          res.end('Not Found');
          return;
        }
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(indexData);
      });
      return;
    }
    res.writeHead(200, { 'Content-Type': getMimeType(filePath) });
    res.end(data);
  });
});

// Listen on both IPv4 and IPv6 by using '::'
server.listen(PORT, '::', () => {
  console.log(`🧡 KINREL Flutter Web Server running on port ${PORT}`);
  console.log(`📁 Serving static files from: ${WEB_ROOT}`);
  console.log(`🌐 Listening on [::] (IPv4 + IPv6)`);
});
