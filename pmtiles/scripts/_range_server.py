"""
_range_server.py — HTTP server with Range support + CORS for serving PMTiles.

Suitable for local dev only. For production, use Cloudflare R2, S3+CloudFront,
or any static host that supports HTTP Range requests.

Python's SimpleHTTPRequestHandler gained native Range support in 3.13.
This module back-ports Range support for 3.7+ by overriding send_head().
"""
import http.server
import os
import socketserver
import sys
import urllib.parse
import re

OUTPUT_DIR = sys.argv[1]
PORT = int(sys.argv[2])

RANGE_RE = re.compile(r'bytes=(\d*)-(\d*)')


class PMTilesHandler(http.server.SimpleHTTPRequestHandler):
    """Serve files from OUTPUT_DIR with:
       - HTTP Range requests (RFC 7233) — required by PMTiles
       - CORS Access-Control-Allow-Origin: * — for cross-origin tile fetches
       - Cache-Control: immutable — PMTiles archives are versioned by filename
       - Content-Type: application/octet-stream for .pmtiles

    NOTE: protocol_version MUST be HTTP/1.1 for Range requests to work.
    """
    protocol_version = "HTTP/1.1"

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

    def send_head(self):
        """Override to add Range request support (RFC 7233)."""
        path = self.translate_path(self.path)
        if not os.path.exists(path) or os.path.isdir(path):
            return super().send_head()

        try:
            file_size = os.path.getsize(path)
        except OSError:
            return super().send_head()

        # Parse Range header
        range_header = self.headers.get('Range')
        if not range_header:
            # No Range request — serve the whole file
            return super().send_head()

        m = RANGE_RE.match(range_header)
        if not m:
            self.send_error(400, "Invalid Range header")
            return None

        start_str, end_str = m.group(1), m.group(2)
        if start_str == '' and end_str == '':
            self.send_error(400, "Invalid Range header")
            return None

        # Suffix range: bytes=-500 → last 500 bytes
        if start_str == '':
            suffix = int(end_str)
            if suffix == 0:
                self.send_error(416, "Requested Range Not Satisfiable")
                return None
            start = max(0, file_size - suffix)
            end = file_size - 1
        else:
            start = int(start_str)
            end = int(end_str) if end_str else file_size - 1
            if end >= file_size:
                end = file_size - 1

        if start > end or start >= file_size:
            self.send_header('Content-Range', f'bytes */{file_size}')
            self.send_error(416, "Requested Range Not Satisfiable")
            return None

        # Send 206 Partial Content
        self.send_response(206)
        self.send_header('Content-Type', self.guess_type(path))
        self.send_header('Content-Range', f'bytes {start}-{end}/{file_size}')
        self.send_header('Content-Length', str(end - start + 1))
        self.send_header('Accept-Ranges', 'bytes')
        self.end_headers()

        # Return a file-like object positioned at `start`
        f = open(path, 'rb')
        f.seek(start)
        # Wrap so that only (end-start+1) bytes are read
        return _RangeFile(f, end - start + 1)


class _RangeFile:
    """File wrapper that limits reads to a specific byte count."""

    def __init__(self, f, length):
        self._f = f
        self._remaining = length

    def read(self, size=-1):
        if self._remaining <= 0:
            return b''
        if size < 0 or size > self._remaining:
            size = self._remaining
        data = self._f.read(size)
        self._remaining -= len(data)
        return data

    def close(self):
        self._f.close()

    def __iter__(self):
        while True:
            chunk = self.read(64 * 1024)
            if not chunk:
                break
            yield chunk


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
    print(f"  Range:   supported (HTTP/1.1 + RFC 7233)")
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
