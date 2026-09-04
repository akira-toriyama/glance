/// `--help`, rendered from `Defaults` so the quoted numbers are the ones
/// the panel uses. GlanceApp only prints it. README § CLI is this text
/// verbatim (build.yml fails when they differ), and CLAUDE.md points here
/// instead of carrying a third copy.
public enum HelpText {
    public static func render(version: String) -> String {
        let width = Int(Defaults.width)
        let fontSize = Int(Defaults.fontSize)
        let minH = Int(Defaults.minHeight)
        let maxH = Int(Defaults.maxHeight)
        return """
        glance \(version) — display stdin in a non-activating macOS popover

        glance reads stdin and shows it in a floating NSPanel. The panel does
        NOT take keyboard focus from the source app, so it's safe to use as
        the result-display end of a selection-driven pipeline.

        USAGE
          some-cmd | glance [flags]

        FLAGS
          --title <s>          window title
          --at <x> <y>         anchor (Cocoa screen coords, Y-up); panel top-
                               left at this point. Default: screen center.
                               Clamped to the visible screen area.
          --markdown           render stdin as Markdown (CommonMark + GFM:
                               tables, task lists, strikethrough)
          --copy               also copy stdin to clipboard (pbcopy)
          --auto-close <s>     dismiss after N seconds (N > 0)
          --width <px>         panel width  (default \(width); > 0)
          --height <px>        panel height (default: auto-size,
                               clamped \(minH)–\(maxH)pt; > 0)
          --font-size <pt>     body font size (default \(fontSize); markdown
                               headings scale relative to this; > 0)
          --theme <name>       Highlightr theme for code blocks (default
                               \(Defaults.theme)). Try: nord, monokai-sublime,
                               vs2015, github-dark, etc.
          --no-highlight       skip syntax highlighting entirely (faster
                               start, no JSCore boot)
          --hud                borderless rounded-corner mode for short
                               toast-style display (no title bar)
          --sticky             only the title-bar X button dismisses the
                               panel (no click-outside, no auto-close).
                               Esc / ⌘W still work as a safety valve.
                               Mutually exclusive with --hud and
                               --auto-close.
          --version / -V       print version, exit
          --help / -h          print this help, exit

        EXIT CODES
          0   shown successfully (after dismissal)
          2   bad flag / parse error (unknown flag, missing or
              non-numeric value, a sized option ≤ 0, --sticky with
              --hud or --auto-close)

        EXAMPLES
          printf 'Hello world' | glance --title 'Greeting'
          curl -s ... | jq -r .text | glance --title 'DeepL' --at 800 500
          claude -p '...' | glance --markdown --title 'Summary'

        See: https://github.com/akira-toriyama/glance
        """
    }
}
