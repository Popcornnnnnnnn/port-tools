#!/usr/bin/env python3

import argparse
import json
import ssl
from http.server import ThreadingHTTPServer

from http_fixture import Handler


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=51741)
    parser.add_argument("--cert", required=True)
    parser.add_argument("--key", required=True)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(args.cert, args.key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
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
