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
        # GFM + syntax highlight + table + blockquote + task list を
        # ひとまとめに、glance の今の能力が一画面で確認できる demo。
        # auto-close を入れないので user が明示的に dismiss するまで残る。
        # NOTE: 単引用符内の \(name) 等は意図的に shell expansion させない
        # markdown 内の文字列なので SC2016 を disable。
        # shellcheck disable=SC2016
        printf '%s' '# glance demo

`some-cmd` の結果を non-activating panel に表示します。**focus** は
奪わないので、元のアプリで打鍵し続けられます。

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

- [x] swift-markdown 採用
- [x] Highlightr で syntax highlight
- [ ] あなたが Esc で閉じる

> blockquote: 左バー + muted color。
> 段落跨ぎでも継続するか確認。

---

Esc / ⌘W / panel 外クリックで dismiss。
' | ./bin/glance --title "glance demo" --markdown --width 540
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
