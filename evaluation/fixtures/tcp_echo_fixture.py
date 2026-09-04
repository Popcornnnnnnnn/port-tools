#!/usr/bin/env python3

import argparse
import json
import socketserver


class EchoHandler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        data = self.request.recv(4096)
        if data:
            self.request.sendall(data)


class ThreadingTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=51740)
    args = parser.parse_args()

    with ThreadingTCPServer((args.host, args.port), EchoHandler) as server:
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
            print(json.dumps({"event": "stopped"}), flush=True)


if __name__ == "__main__":
    main()
