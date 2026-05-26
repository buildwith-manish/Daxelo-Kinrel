#!/bin/bash
trap '' SIGHUP SIGINT SIGTERM

while true; do
  node -e "
const http = require('http');
const fs = require('fs');
const path = require('path');
const WEB = '/home/z/my-project/Daxelo-Kinrel-App/build/web';
const M = {'.html':'text/html','.js':'application/javascript','.json':'application/json','.css':'text/css','.png':'image/png','.svg':'image/svg+xml','.ico':'image/x-icon','.wasm':'application/wasm','.ttf':'font/ttf','.woff2':'font/woff2'};
http.createServer((q, r) => {
  let p = path.join(WEB, q.url==='/' ? 'index.html' : q.url);
  fs.readFile(p, (e, d) => {
    if(e){fs.readFile(path.join(WEB,'index.html'),(e2,d2)=>{if(e2){r.writeHead(404);r.end();return;}r.writeHead(200,{'Content-Type':'text/html'});r.end(d2);});return;}
    r.writeHead(200,{'Content-Type':M[path.extname(p)]||'application/octet-stream'});r.end(d);
  });
}).listen(3000,'0.0.0.0');
" 2>/dev/null
  sleep 0.3
done
