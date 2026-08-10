#!/bin/sh
# Install glance to ~/.local/bin/glance. Not a daemon, so no launchd
# registration — just put the single-shot CLI on PATH.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin/glance"

"$DIR/build.sh"

mkdir -p "$HOME/.local/bin"
install -m 0755 "$DIR/bin/glance" "$BIN"

echo "installed: $BIN"

# On PATH? If not, say how.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "note: $HOME/.local/bin is not on PATH. Add it in .zshrc / .bashrc:"
       echo "      export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
