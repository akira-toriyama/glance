# Security Policy

## Supported versions

The latest release on `main` is supported. Older releases get fixes only by
upgrading.

## Security model

glance has the following characteristics; use it with these understood.

- **It displays stdin content as-is in a native panel.** When the upstream
  of the pipeline may carry untrusted content (curl output of an untrusted
  URL, …), the risk of `[link](javascript:...)` etc. in `--markdown` mode
  depends on how the selectable `NSTextView` opens, on click, the URL our
  own markdown renderer (`MarkdownRenderer.visitLink`) embedded as a
  `.link` attribute (AppKit / NSWorkspace link handling). Foundation's
  `NSAttributedString(markdown:)` is not currently used (today a
  `javascript:` URL does not execute, but note newer macOS could change
  that).

- **No Accessibility permission needed.** glance itself never uses the OS
  Accessibility APIs — only its triggers (a chord hotkey, text-selection
  watching, …) may.

- **No network access.** Any HTTP call is the pipeline upstream's job
  (curl, …); glance only displays its output.

## Reporting a vulnerability

Report via GitHub **Security Advisories** (private vulnerability
reporting). Never in a public issue.
