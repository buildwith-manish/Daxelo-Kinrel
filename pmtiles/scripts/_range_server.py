"""
_range_server.py — HTTP server with Range support + CORS for serving PMTiles.

Suitable for local dev only. For production, use Cloudflare R2, S3+CloudFront,
or any static host that supports HTTP Range requests.
"""
import http.server
import os
import socketserver
import sys
import urllib.parse

OUTPUT_DIR = sys.argv[1]
PORT = int(sys.argv[2])

class PMTilesHandler(http.server.SimpleHTTPRequestHandler):
    """Serve files from OUTPUT_DIR with:
       - HTTP Range requests (RFC 7233) — required by PMTiles
       - CORS Access-Control-Allow-Origin: * — for cross-origin tile fetches
       - Cache-Control: immutable — PMTiles archives are versioned by filename
       - Content-Type: application/octet-stream for .pmtiles
    """
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=OUTPUT_DIR, **kwargs)

    def end_headers(self):
        # CORS — open in dev. In prod, restrict to your domain.
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Range, If-None-Match')
        self.send_header('Access-Control-Expose-Headers', 'Content-Range, Content-Length, ETag')

        # Cache — file is immutable (filename includes version)
        if self.path.endswith('.pmtiles'):
            self.send_header('Cache-Control', 'public, max-age=31536000, immutable')
            self.send_header('Content-Type', 'application/octet-stream')

        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()


class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


if __name__ == '__main__':
    if not os.path.isdir(OUTPUT_DIR):
        print(f"ERROR: output dir not found: {OUTPUT_DIR}", file=sys.stderr)
        sys.exit(1)
    server = ThreadingHTTPServer(('0.0.0.0', PORT), PMTilesHandler)
    print(f"PMTiles dev server")
    print(f"  Serving: {OUTPUT_DIR}")
    print(f"  URL:     http://localhost:{PORT}/")
    print(f"  Range:   supported")
    print(f"  CORS:    permissive (dev only)")
    print(f"")
    print(f"  Example PMTiles URL for use in map style:")
    print(f"    pmtiles://http://localhost:{PORT}/mumbai.pmtiles")
    print(f"")
    print(f"  Ctrl+C to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping...")
        server.shutdown()
