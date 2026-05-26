#!/bin/sh
# glance を ~/.local/bin/glance に配置する。daemon ではないので launchd
# 登録は不要 — single-shot CLI として PATH に通すだけ。
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin/glance"

"$DIR/build.sh"

mkdir -p "$HOME/.local/bin"
install -m 0755 "$DIR/bin/glance" "$BIN"

echo "installed: $BIN"

# PATH 通ってる? 通ってなければ案内。
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "note: $HOME/.local/bin が PATH に無い。.zshrc / .bashrc に追加してください:"
       echo "      export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
