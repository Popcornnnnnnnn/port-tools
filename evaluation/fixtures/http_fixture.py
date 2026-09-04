#!/usr/bin/env python3

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


HTML = b"""<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>port-tools fixture</title></head>
<body><main><h1>port-tools fixture</h1><p id="status">healthy</p></main></body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    server_version = "port-tools-fixture/0.1"

    def _record(self) -> None:
        fields = {
            "method": self.command,
            "path": self.path,
            "host": self.headers.get("Host"),
            "user_agent": self.headers.get("User-Agent"),
            "forwarded": self.headers.get("Forwarded"),
            "x_forwarded_for": self.headers.get("X-Forwarded-For"),
            "x_forwarded_host": self.headers.get("X-Forwarded-Host"),
            "x_forwarded_proto": self.headers.get("X-Forwarded-Proto"),
        }
        print(json.dumps(fields, ensure_ascii=False), flush=True)

    def _respond(self, include_body: bool) -> None:
        self._record()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(HTML)))
        self.end_headers()
        if include_body:
            self.wfile.write(HTML)

    def do_HEAD(self) -> None:
        self._respond(include_body=False)

    def do_GET(self) -> None:
        self._respond(include_body=True)

    def log_message(self, _format: str, *_args: object) -> None:
        return


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=51739)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(
        json.dumps(
            {"event": "listening", "host": args.host, "port": args.port},
            ensure_ascii=False,
        ),
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        print(json.dumps({"event": "stopped"}), flush=True)


if __name__ == "__main__":
    main()
