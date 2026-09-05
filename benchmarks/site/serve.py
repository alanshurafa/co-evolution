#!/usr/bin/env python3
"""Preview the static eval site on registered frontend port 3016.

Port registry: C:/Users/alan/localhost.md. Only public site files are served.
"""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

if __name__ == '__main__':
    handler = partial(SimpleHTTPRequestHandler, directory=str(Path(__file__).resolve().parent / 'public'))
    server = ThreadingHTTPServer(('127.0.0.1', 3016), handler)
    print('Co-Evolution eval observatory: http://127.0.0.1:3016', flush=True)
    server.serve_forever()
