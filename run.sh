#!/bin/sh
# glance を verbose でローカル起動する dev ループ。glance は daemon を
# 持たないので、他アプリの `./run.sh`(常駐アプリを <APP>_DEBUG 付きで起動)
# に相当するのは GLANCE_DEBUG=1 で demo を起動する事 ＝ 無印 ./run.sh。
# 本番配置 (~/.local/bin) は ./install.sh に分離 (= ./run.sh --install)。
#
#   ./run.sh               build + verbose demo 起動 (GLANCE_DEBUG=1、panel + /tmp/glance.log)
#   ./run.sh --demo / -d   同上 (明示)
#   ./run.sh --install/-i  ~/.local/bin に配置 (= ./install.sh、静音)
#   ./run.sh --help        使い方
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

case "${1:-}" in
    ""|-d|--demo)
        ./build.sh
        # GFM + syntax highlight + table + blockquote + task list を
        # ひとまとめに、glance の今の能力が一画面で確認できる demo。
        # auto-close を入れないので user が明示的に dismiss するまで残る。
        # dev loop なので GLANCE_DEBUG=1 付き — 引数 / stdin / panel frame /
        # dismiss の trace が stderr + /tmp/glance.log に出る (通常 install は静か)。
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
