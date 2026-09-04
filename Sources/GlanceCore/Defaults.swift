/// The numbers ViewerPanel lays the panel out with and `--help` quotes. One
/// home, so the help text, README § CLI (a verbatim paste of `--help` that
/// build.yml diffs) and the panel cannot disagree — they did (380 / 16 /
/// 80–600 / 28 were typed in three places).
public enum Defaults {
    public static let width: Double = 380
    /// 16pt is a step above macOS's standard body (13pt) — right for the
    /// "glance at it" use. Markdown headings scale from it by multipliers.
    public static let fontSize: Double = 16
    /// Auto-sized height clamp (an explicit `--height` is honored as is).
    public static let minHeight: Double = 80
    /// `--hud` has no title bar and shows short toasts, so it may be shorter.
    public static let hudMinHeight: Double = 40
    public static let maxHeight: Double = 600
    /// Title-bar height added to the auto-sized height (0 under `--hud`).
    public static let titleBarSlack: Double = 28
    /// NSTextView container inset (x / y), both sides.
    public static let textInsetX: Double = 18
    public static let textInsetY: Double = 14
    /// Highlightr theme for `--theme` when unset.
    public static let theme = "atom-one-dark"
}
