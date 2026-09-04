#!/bin/sh
set -eu

fixture_port="${1:-51743}"
fixture_script="$(CDPATH= cd -- "$(dirname "$0")" && pwd)/http_fixture.py"

cd /tmp
python3 "$fixture_script" --host 127.0.0.1 --port "$fixture_port" &
child_pid=$!
trap 'kill -TERM "$child_pid" 2>/dev/null || true' INT TERM EXIT
wait "$child_pid"
