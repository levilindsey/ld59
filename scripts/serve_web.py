#!/usr/bin/env python3
"""
Local HTTP server for the Kittenbaticorn web build.

The web export uses SharedArrayBuffer (threads_support=true) and
the kbterrain GDExtension is dlink'd. Browsers require these
response headers for cross-origin isolation:

    Cross-Origin-Opener-Policy:  same-origin
    Cross-Origin-Embedder-Policy: require-corp

Standard `python -m http.server` doesn't set them, so this script
serves `build/web/` with the right headers attached.

Usage:
    python scripts/serve_web.py [port]
"""

from __future__ import annotations

import http.server
import os
import socketserver
import sys


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVE_DIR = os.path.join(REPO_ROOT, "build", "web")


class IsolatedHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        super().end_headers()

    def log_message(self, format: str, *args) -> None:
        sys.stderr.write(
            "[serve_web] %s - %s\n" % (self.address_string(), format % args)
        )


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8060
    if not os.path.isdir(SERVE_DIR):
        sys.stderr.write(
            "ERROR: build dir not found: %s\n"
            "Run a web export first.\n" % SERVE_DIR
        )
        sys.exit(1)
    os.chdir(SERVE_DIR)

    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(
        ("127.0.0.1", port), IsolatedHandler
    ) as httpd:
        url = "http://127.0.0.1:%d/index.html" % port
        sys.stderr.write(
            "Serving %s on %s (Ctrl+C to stop)\n" % (SERVE_DIR, url)
        )
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            sys.stderr.write("\nstopped\n")


if __name__ == "__main__":
    main()
