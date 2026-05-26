const http = require('http');
const httpProxy = require('http');

const TARGET_PORT = 3000;
const PROXY_PORT = 3002;

const server = http.createServer((req, res) => {
  const options = {
    hostname: '127.0.0.1',
    port: TARGET_PORT,
    path: req.url,
    method: req.method,
    headers: req.headers,
  };

  const proxyReq = http.request(options, (proxyRes) => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res);
  });

  proxyReq.on('error', (err) => {
    res.writeHead(502);
    res.end('Bad Gateway');
  });

  req.pipe(proxyReq);
});

// Try to listen on IPv6
server.listen(PROXY_PORT, '::', () => {
  console.log(`IPv6→IPv4 proxy running on [::]:${PROXY_PORT} → 127.0.0.1:${TARGET_PORT}`);
}).on('error', (err) => {
  // Fall back to IPv4
  server.listen(PROXY_PORT, '0.0.0.0', () => {
    console.log(`Proxy running on 0.0.0.0:${PROXY_PORT} → 127.0.0.1:${TARGET_PORT}`);
  });
});
