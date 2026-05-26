#!/bin/sh
# Kill any glance instances that have stuck panels open. glance は
# one-shot CLI なので通常は user dismiss で自滅するが、稀に panel が
# 残り続けるときに使う。Safe to run when nothing is running (no-op)。
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
