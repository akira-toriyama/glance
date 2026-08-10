#!/bin/sh
# Kill any glance instances that have stuck panels open. glance is a
# one-shot CLI that normally exits on user dismiss; use this on the rare
# occasion a panel lingers. Safe to run when nothing is running (no-op).
#
#   ./stop.sh
set -e

pkill -x glance          2>/dev/null || true
pkill -f '/bin/glance'   2>/dev/null || true

remaining="$(pgrep -fl glance | grep -vE 'stop\.sh|run\.sh|grep' || true)"
if [ -n "$remaining" ]; then
    echo "warning: some glance instances survived:" >&2
    echo "$remaining" >&2
    exit 1
fi
echo "stopped: all glance instances"
