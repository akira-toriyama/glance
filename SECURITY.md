# Security Policy

## Supported

Only the latest `main`.

## Security model

glance has the following characteristics; use it with these understood.

glance has the following operational characteristics. Users should understand
them:

- **It displays stdin content as-is in a native panel.** When the upstream
  of the pipeline may carry untrusted content (curl output of an untrusted
  URL, …), the risk of `[link](javascript:...)` etc. in `--markdown` mode
  depends on how the selectable `NSTextView` opens, on click, the URL our
  own markdown renderer (`MarkdownRenderer.visitLink`) embedded as a
  `.link` attribute (AppKit / NSWorkspace link handling). Foundation's
  `NSAttributedString(markdown:)` is not currently used (today a
  `javascript:` URL does not execute, but note newer macOS could change
  that).
  glance renders stdin verbatim. If upstream content is untrusted, the
  safety of `--markdown` rendering depends on how AppKit's selectable
  `NSTextView` opens the `.link`-attributed URLs that glance's own
  markdown renderer (`MarkdownRenderer.visitLink`) embeds — not on
  Foundation's `NSAttributedString(markdown:)`, which glance no longer
  uses. Current macOS doesn't execute `javascript:` URLs from markdown
  links, but future behavior is not guaranteed.

- **No Accessibility permission needed.** glance itself never uses the OS
  Accessibility APIs — only its triggers (a chord hotkey, text-selection
  watching, …) may.
  glance does NOT require Accessibility permission. The upstream trigger
  (a chord hotkey, or a text-selection observer) may need it; glance
  itself reads stdin and shows a panel.

- **No network access.** Any HTTP call is the pipeline upstream's job
  (curl, …); glance only displays its output.
  glance does NOT make network calls. Any HTTP fetches happen upstream
  (curl, etc.); glance only displays their output.

## Reporting a vulnerability

Report via GitHub **Security Advisories** (private vulnerability
reporting). Never in a public issue.
Please report via GitHub Security Advisories (private vulnerability
reporting). Do not file public issues for vulnerabilities.
