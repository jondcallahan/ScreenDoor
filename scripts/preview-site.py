#!/usr/bin/env python3
"""Serve the marketing site locally, including its Vercel clean URLs."""

from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


SITE_ROOT = Path(__file__).resolve().parent.parent / "site"


class SiteHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(SITE_ROOT), **kwargs)

    def translate_path(self, path):
        resolved = Path(super().translate_path(path))
        if not resolved.exists() and not resolved.suffix:
            html = resolved.with_suffix(".html")
            if html.is_file():
                return str(html)
        return str(resolved)


if __name__ == "__main__":
    with ThreadingHTTPServer(("127.0.0.1", 8000), SiteHandler) as server:
        print("Preview website: http://127.0.0.1:8000 (Ctrl+C to stop)", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
