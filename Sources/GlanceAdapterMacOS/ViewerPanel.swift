import AppKit
import GlanceCore
import Palette
import PaletteKit

/// The viewer showing the input text in a native NSPanel. **Never stealing
/// focus** is the design core — achieved with the `.nonactivatingPanel`
/// style + `becomesKeyOnlyIfNeeded`.
///
/// After showing, the user's dismiss (Esc / click outside the panel) is
/// expected to call `NSApp.terminate(nil)`. With auto-close set, it
/// self-destructs after the interval.
@MainActor
public final class ViewerPanel {
    private let panel: NSPanel
    private var clickOutsideMonitor: Any?
    private var keyDownMonitor: Any?
    /// `--sticky`: disables outside-click and auto-close; the X button is
    /// the primary dismiss. Esc / ⌘W remain as the safety valve.
    private let sticky: Bool

    /// Fade-in/out duration. Too short looks like a pop; too long collides
    /// with mousing. Matched to Notification Center's ~0.15s.
    private static let fadeDuration: TimeInterval = 0.14

    /// Line-spacing / padding / block-level decoration constants — following
    /// MacDown GitHub2.css etc., translated into native NSAttributedString.
    /// Sizes the help text quotes live in `Defaults` (GlanceCore).
    private static let bodyLineSpacing: CGFloat = 4
    private static let bodyTextInset = NSSize(width: Defaults.textInsetX,
                                              height: Defaults.textInsetY)
    private static let codeBlockIndent: CGFloat = 10
    private static let codeBlockParagraphSpacing: CGFloat = 6
    private static let blockquoteIndent: CGFloat = 16

    /// glance's panel chrome derives from ONE fixed dark sill preset.
    /// catppuccin-mocha (#1E1E2E ≈ the old hardcoded #1E1E1E) is chosen, and
    /// the bg / body / markdown role colors come from resolve()'s derivation
    /// recipes + the ink() tiers (plan atelier — the north star: never again
    /// say "imitate facet's theme"). No theme switching — glance is an
    /// ephemeral result-view popover, not a theming surface. Highlightr's
    /// `--theme` (code syntax) is orthogonal and untouchable (a separate
    /// axis; its 271 themes stay alone).
    /// Held as a typed `Theme` — passing a raw string to `paletteFor` is
    /// TOTAL over an untyped domain, silently falling to `terminal` when a
    /// theme leaves the catalog (exactly how sill v1.36.0's removal of
    /// `catppuccin-latte` broke wand). A case is a declaration: if it
    /// disappears, the compile error tells you.
    private static let chromeTheme = Theme.catppuccinMocha
    private static func chromePalette() -> ResolvedPalette {
        // forceDark: the theme is dark, so pin NSTextView selection / find
        // bar / scroller system chrome dark (successor of the old .darkAqua
        // forcing).
        resolve(chromeTheme.spec, forceDark: true)
    }

    /// The HUD-mode corner radius — about a macOS notification banner's.
    private static let hudCornerRadius: CGFloat = 10

    public init(text: String, args: Args) {
        self.sticky = args.sticky
        // Resolve the fixed dark chrome from sill once. Panel bg / body
        // color / markdown role colors all derive from it.
        let palette = Self.chromePalette()
        let chromeBackground = palette.background ?? NSColor(white: 0.118, alpha: 1)
        // Configure the syntax highlighter from the CLI. `--no-highlight`
        // never boots Highlightr at all (skipping the ~30-100ms JSCore
        // start).
        MarkdownRenderer.configureSyntaxHighlighter(
            theme: args.theme ?? Defaults.theme, enabled: !args.noHighlight)

        // Passed as MarkdownRenderer.Style.baseFontSize; the heading
        // hierarchy derives from it by multipliers.
        let fontSize = CGFloat(args.fontSize ?? Defaults.fontSize)
        let isHud = args.hud

        let w = CGFloat(args.width ?? Defaults.width)
        let requestedH = args.height.map { CGFloat($0) }

        // Assemble the contentView first, then size the panel by the text's
        // natural height. An explicit --height is honored (no clamp).
        let textInset = Self.bodyTextInset
        let attributed = Self.renderAttributed(
            text: text, markdown: args.markdown, fontSize: fontSize,
            palette: palette)

        let contentWidth = w
        let textWidth = contentWidth - textInset.width * 2
        let naturalTextHeight = attributed.boundingRect(
            with: NSSize(width: textWidth,
                         height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        // HUD has no title bar, so no slack subtracted.
        let titleBarSlack = CGFloat(isHud ? 0 : Defaults.titleBarSlack)
        let naturalPanelHeight = ceil(naturalTextHeight)
            + textInset.height * 2
            + titleBarSlack
        let minH = CGFloat(isHud ? Defaults.hudMinHeight : Defaults.minHeight)
        let maxH = CGFloat(Defaults.maxHeight)
        let autoH = min(max(naturalPanelHeight, minH), maxH)
        let h = requestedH ?? autoH

        // The anchor sits at the menu's top-left; without --at, screen
        // center. Coordinates hugging the screen edge are clamped so the
        // panel never overflows.
        let frame: NSRect = {
            let baseRect: NSRect
            if let anchor = args.at {
                // Cocoa coordinates (Y grows upward). The anchor = the
                // panel's top-left, and the panel extends downward, so Y - h
                // yields the actual frame.
                baseRect = NSRect(x: CGFloat(anchor.x),
                                  y: CGFloat(anchor.y) - h,
                                  width: w,
                                  height: h)
            } else if let screen = NSScreen.main {
                let f = screen.visibleFrame
                baseRect = NSRect(x: f.midX - w / 2, y: f.midY - h / 2,
                                  width: w, height: h)
            } else {
                baseRect = NSRect(x: 200, y: 200, width: w, height: h)
            }
            return Self.clampToScreen(baseRect)
        }()

        let styleMask: NSWindow.StyleMask = isHud
            ? [.nonactivatingPanel, .borderless]
            : [.nonactivatingPanel, .titled, .closable, .resizable]

        panel = NSPanel(
            contentRect: frame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false)
        if !isHud {
            panel.title = args.title
            panel.titlebarAppearsTransparent = false
        }
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces,
                                    .fullScreenAuxiliary,
                                    .transient]
        panel.isMovableByWindowBackground = true
        // The chrome background is the sill preset's (catppuccin-mocha)
        // background. In HUD mode the panel itself goes transparent and the
        // root's rounded layer shows the rounded dark; otherwise the panel
        // lays chromeBackground directly.
        if palette.forceDarkAqua {
            panel.appearance = NSAppearance(named: .darkAqua)
        }
        if isHud {
            panel.isOpaque = false
            panel.backgroundColor = .clear
        } else {
            panel.isOpaque = true
            panel.backgroundColor = chromeBackground
        }
        panel.hasShadow = true
        panel.alphaValue = 0  // for the fade-in (present interpolates to 1)

        // root: the fixed chrome background's CGColor. A layer bg never
        // tracks appearance dynamically, so windowBackgroundColor would bake
        // in the current app appearance (often light at launch),
        // contradicting the panel's darkAqua forcing. chromeBackground is an
        // opaque concrete color — fine.
        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        root.autoresizingMask = [.width, .height]
        root.wantsLayer = true
        root.layer?.backgroundColor = chromeBackground.cgColor
        if isHud {
            root.layer?.cornerRadius = Self.hudCornerRadius
            root.layer?.masksToBounds = true
        }

        // contentView: a scrollable NSTextView. Its background is
        // transparent, letting the root's dark show through (the root is
        // fixed dark, so the result is always a VSCode-like dark bg).
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: frame.size))
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]

        // Explicit TextKit 1 construction, to insert GlanceLayoutManager
        // (the inline-code pill painter). `NSTextView(frame:)` builds its own
        // storage / layout, so assemble the stack by hand and pass it via
        // textContainer. NSTextTable also runs on TextKit 1, so code blocks /
        // tables keep working.
        let textStorage = NSTextStorage()
        let layoutManager = GlanceLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: scroll.bounds.size)
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: scroll.bounds,
                                  textContainer: textContainer)
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = textInset
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = palette.foreground
        textView.usesFindBar = true

        textView.textStorage?.setAttributedString(attributed)
        // foregroundColor / typography are settled inside renderAttributed
        // (each run carries its baked sill role color). Overriding the whole
        // textView's color here would erase per-run colors like the
        // blockquote's muted — hands off.

        scroll.documentView = textView
        root.addSubview(scroll)
        panel.contentView = root
    }

    private static func renderAttributed(text: String,
                                         markdown: Bool,
                                         fontSize: CGFloat,
                                         palette: ResolvedPalette) -> NSAttributedString {
        if markdown {
            let renderer = MarkdownRenderer(
                style: rendererStyle(fontSize: fontSize, palette: palette))
            return renderer.render(text)
        }
        let p = NSMutableParagraphStyle()
        p.lineSpacing = bodyLineSpacing
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: palette.foreground,
            .paragraphStyle: p,
        ])
    }

    /// The Style handed to MarkdownRenderer. Typography constants come from
    /// ViewerPanel, colors from the resolved palette. The neutral
    /// white-alpha overlays derive from sill's shared `ink` tiers
    /// (foreground-tinted, so theme-tracking): wash ≈ inline pill / outer
    /// rules; subtle ≈ block & header bg, heading underline; strong ≈ the
    /// blockquote bar.
    private static func rendererStyle(fontSize: CGFloat,
                                      palette: ResolvedPalette) -> MarkdownRenderer.Style {
        MarkdownRenderer.Style(
            baseFontSize: fontSize,
            bodyLineSpacing: bodyLineSpacing,
            foreground: palette.foreground,
            tertiary: palette.tertiary,
            primary: palette.primary,
            border: palette.border,
            inlineCodeBackground: palette.ink(.wash, of: .foreground),
            codeBlockBackground: palette.ink(.subtle, of: .foreground),
            tableHeaderBackground: palette.ink(.subtle, of: .foreground),
            tableOuterBorder: palette.ink(.wash, of: .foreground),
            blockquoteBar: palette.ink(.strong, of: .foreground),
            headingUnderline: palette.ink(.subtle, of: .foreground),
            codeBlockIndent: codeBlockIndent,
            blockquoteIndent: blockquoteIndent,
            codeBlockParagraphSpacing: codeBlockParagraphSpacing)
    }

    /// Pulls an `--at` that dug into the screen edge back inside
    /// visibleFrame. Matters when the upstream pipeline (the trigger's
    /// selection coordinates) is near the right edge.
    private static func clampToScreen(_ rect: NSRect) -> NSRect {
        guard let screen = NSScreen.main else { return rect }
        let vf = screen.visibleFrame
        var r = rect
        if r.maxX > vf.maxX { r.origin.x = vf.maxX - r.width }
        if r.minX < vf.minX { r.origin.x = vf.minX }
        if r.maxY > vf.maxY { r.origin.y = vf.maxY - r.height }
        if r.minY < vf.minY { r.origin.y = vf.minY }
        return r
    }

    /// Show the panel. It orders front without `makeKey`, so the original
    /// app keeps keyboard focus. With `copy=true` the shown content also
    /// goes to pbcopy (for the paste-the-translation-later flow).
    public func present(autoCloseSeconds: Double?, copy: Bool = false,
                        copyText: String = "") {
        Log.debug("present: frame=\(panel.frame) sticky=\(sticky) "
            + "autoClose=\(autoCloseSeconds.map { String($0) } ?? "off") copy=\(copy)")
        if copy && !copyText.isEmpty {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(copyText, forType: .string)
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeDuration
            panel.animator().alphaValue = 1
        }

        // Close on a click outside the panel. Deliberately not installed
        // under `--sticky` — Esc / ⌘W / the X button become the only
        // dismiss paths.
        if !sticky {
            clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown,
                           .otherMouseDown]) { [weak self] _ in
                self?.dismiss()
            }
        }

        // Catch Esc / ⌘W from key input inside the panel (the panel CAN
        // become key = becomesKeyOnlyIfNeeded makes it key only on a
        // textView click). Kept under `--sticky` too (the keyboard safety
        // valve; ⌘C copies without closing / a mis-press can't wedge you).
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown) { [weak self] ev in
            if ev.keyCode == 53 {   // Esc
                self?.dismiss()
                return nil
            }
            // ⌘W is macOS's conventional "close" key — insurance when Esc
            // slips through.
            if ev.modifierFlags.contains(.command),
               ev.charactersIgnoringModifiers == "w" {
                self?.dismiss()
                return nil
            }
            return ev
        }

        // No auto-close under `--sticky` (parseArgs already rejects the
        // combination; this is a just-in-case double-check).
        if !sticky, let seconds = autoCloseSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                [weak self] in self?.dismiss()
            }
        }
    }

    private func dismiss() {
        Log.debug("dismiss")
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }
        if let m = keyDownMonitor {
            NSEvent.removeMonitor(m)
            keyDownMonitor = nil
        }
        // Fade out, then close + terminate. An immediate close blinks out.
        // The exit rides a timer, not the animation's completionHandler:
        // with the display asleep Core Animation never completes, and the
        // process lived until killed (measured 2026-09-05: `--auto-close 1`
        // logged dismiss at 1 s and was still alive 60 s later; awake, the
        // same run exits in 1.3 s). The GCD timer fires either way.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDuration) { [panel] in
            panel.close()
            NSApplication.shared.terminate(nil)
        }
    }
}
