import http.server, os, urllib.parse

PROJECT = '/home/z/my-project'

class H(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        p = urllib.parse.urlparse(self.path).path
        if p == '/' or p == '':
            p = '/.next/server/app/index.html'
        else:
            if p.startswith('/_next/'):
                p = '/.next' + p[6:]
            else:
                p = '/public' + p
        fp = PROJECT + p
        if os.path.isfile(fp):
            ext = fp.rsplit('.',1)[-1]
            ct = {'html':'text/html;charset=utf-8','js':'application/javascript','css':'text/css','svg':'image/svg+xml','woff2':'font/woff2','json':'application/json','png':'image/png','ico':'image/x-icon'}.get(ext,'application/octet-stream')
            self.send_response(200)
            self.send_header('Content-Type', ct)
            self.send_header('Content-Length', os.path.getsize(fp))
            self.end_headers()
            with open(fp, 'rb') as f:
                while True:
                    chunk = f.read(8192)
                    if not chunk: break
                    self.wfile.write(chunk)
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *a): pass

http.server.HTTPServer(('', 3000), H).serve_forever()
