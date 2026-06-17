# Security Policy

## サポート範囲 / Supported

最新の `main` のみ。/ Only the latest `main`.

## セキュリティ上の前提 / Security model

glance は次の動作特性を持ちます。利用者はこれを理解した上で使用してください。

glance has the following operational characteristics. Users should understand
them:

- **stdin から受け取った内容をそのまま native panel に表示する**。pipeline
  の上流が信用できないコンテンツ (untrusted URL の curl 出力など) を
  流す可能性がある場合、`--markdown` モードでの `[link](javascript:...)`
  等のリスクは、自前の markdown renderer (`MarkdownRenderer.visitLink`) が
  `.link` 属性として埋め込んだ URL を、選択可能な `NSTextView` がクリック時に
  どう開くか (AppKit / NSWorkspace のリンク処理) に依存する。Foundation の
  `NSAttributedString(markdown:)` は現在使っていない (現状 `javascript:` URL は
  実行されないが、新しい macOS で挙動が変わる可能性は留意)。
  glance renders stdin verbatim. If upstream content is untrusted, the
  safety of `--markdown` rendering depends on how AppKit's selectable
  `NSTextView` opens the `.link`-attributed URLs that glance's own
  markdown renderer (`MarkdownRenderer.visitLink`) embeds — not on
  Foundation's `NSAttributedString(markdown:)`, which glance no longer
  uses. Current macOS doesn't execute `javascript:` URLs from markdown
  links, but future behavior is not guaranteed.

- **Accessibility 権限は不要**。glance 自身は OS の Accessibility API を
  使わない。トリガー元（chord のホットキーやテキスト選択監視など）が
  必要とするだけ。
  glance does NOT require Accessibility permission. The upstream trigger
  (a chord hotkey, or a text-selection observer) may need it; glance
  itself reads stdin and shows a panel.

- **ネットワークアクセスはしない**。任意の HTTP 呼び出しは pipeline 上流
  (curl 等) の責務。glance はその出力を表示するだけ。
  glance does NOT make network calls. Any HTTP fetches happen upstream
  (curl, etc.); glance only displays their output.

## 脆弱性の報告 / Reporting a vulnerability

GitHub の **Security Advisories** (Private vulnerability reporting) から
報告してください。公開 issue には記載しないでください。
Please report via GitHub Security Advisories (private vulnerability
reporting). Do not file public issues for vulnerabilities.
