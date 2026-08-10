#!/bin/sh
# The dev loop launching glance locally, verbose. glance has no daemon, so
# the equivalent of other apps' `./run.sh` (launch the resident app with
# <APP>_DEBUG) is launching the demo with GLANCE_DEBUG=1 = bare ./run.sh.
# Production placement (~/.local/bin) is split into ./install.sh
# (= ./run.sh --install).
#
#   ./run.sh               build + verbose demo (GLANCE_DEBUG=1, panel + /tmp/glance.log)
#   ./run.sh --demo / -d   same, explicit
#   ./run.sh --install/-i  place into ~/.local/bin (= ./install.sh, quiet)
#   ./run.sh --help        usage
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

case "${1:-}" in
    ""|-d|--demo)
        ./build.sh
        # A demo showing glance's current abilities on one screen — GFM +
        # syntax highlight + table + blockquote + task list together.
        # No auto-close, so it stays until the user dismisses explicitly.
        # It is the dev loop, so GLANCE_DEBUG=1 — traces of args / stdin /
        # panel frame / dismiss go to stderr + /tmp/glance.log (a normal
        # install stays quiet).
        # NOTE: \(name) etc. inside single quotes deliberately avoid shell
        # expansion — they are markdown-internal strings, so SC2016 is off.
        # shellcheck disable=SC2016
        printf '%s' '# glance demo

Shows `some-cmd`'s output in a non-activating panel. **Focus** is never
stolen, so you can keep typing in the original app.

## syntax highlight

```swift
import Foundation

struct Greeter {
    let name: String
    func greet() -> String { "Hello, \(name)!" }
}
```

```python
def fibonacci(n: int) -> list[int]:
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return [a]
```

## table / task list / strike

| feature | status |
|---------|--------|
| GFM tables | ✅ |
| task lists | ✅ |
| ~~deprecated~~ | n/a |

- [x] swift-markdown adopted
- [x] syntax highlighting via Highlightr
- [ ] you close this with Esc

> blockquote: left bar + muted color.
> Checking it continues across paragraphs.

---

Dismiss with Esc / ⌘W / a click outside the panel.
' | GLANCE_DEBUG=1 ./bin/glance --title "glance demo" --markdown --width 540
        ;;
    -i|--install)
        exec ./install.sh
        ;;
    --help|-h)
        echo "usage: ./run.sh                build + verbose demo (GLANCE_DEBUG=1)"
        echo "       ./run.sh --demo | -d     same (explicit)"
        echo "       ./run.sh --install | -i  deploy to ~/.local/bin (= ./install.sh)"
        ;;
    *)
        echo "unknown flag: $1" >&2
        exit 2
        ;;
esac
