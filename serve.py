#!/usr/bin/env python3
"""Serves the web build locally with the headers Godot's threaded build needs.

A plain `python -m http.server` will NOT work: without cross-origin isolation
the browser refuses SharedArrayBuffer and the engine never starts.

    python3 serve.py            # serves ./build on port 8080
    python3 serve.py build 3000
"""
import http.server
import socketserver
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "build"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8080


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
    }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    print(f"Wildlight on http://localhost:{PORT}  (serving {ROOT}/)")
    print("If the engine never starts, check window.crossOriginIsolated is true.")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
