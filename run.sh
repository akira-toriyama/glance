#!/bin/sh
# Build + install glance to ~/.local/bin. Daemon は持たないので
# eventfx の run.sh と違って bootstrap は無い。
#
#   ./run.sh              build + install.sh
#   ./run.sh --demo / -d  build + 簡単な smoke test (printf | glance)
#   ./run.sh --help       使い方
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

case "${1:-}" in
    -d|--demo)
        ./build.sh
        printf 'Hello from glance!\n\nThis is a smoke test pipeline.' \
            | ./bin/glance --title "demo" --markdown
        ;;
    --help|-h)
        echo "usage: ./run.sh [--demo|-d]"
        ;;
    "")
        exec ./install.sh
        ;;
    *)
        echo "unknown flag: $1" >&2
        exit 2
        ;;
esac
