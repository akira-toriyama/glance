import AppKit
import GlanceCore
import Palette
import PaletteKit

/// The viewer showing the input text in a native NSPanel. **Never stealing
/// focus** is the design core — achieved with the `.nonactivatingPanel`
/// style + `becomesKeyOnlyIfNeeded`.
///
/// Every dismiss path (Esc / ⌘W / click outside / `--auto-close` / the X
/// button) fades the panel out, closes it and calls `onDismiss`; the App
/// layer ends the process there — the adapter never terminates NSApp.
@MainActor
public final class ViewerPanel {
    private let panel: NSPanel
    private let args: Args
    private let text: String
    private let onDismiss: @MainActor () -> Void
    private var clickOutsideMonitor: Any?
    private var keyDownMonitor: Any?

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

    /// One fixed dark sill preset (catppuccin-mocha, #1E1E2E ≈ the old
    /// hand-tuned #1E1E1E) and no theme switching: glance is a transient
    /// result-view popover, not a themed surface. Highlightr's `--theme`
    /// (code syntax) is a separate axis and stays untouched.
    ///
    /// A typed `Theme`, not a name string: `paletteFor` is total over
    /// strings and silently falls back to `terminal` when a theme leaves
    /// the catalog (how sill v1.36.0's removal of `catppuccin-latte` broke
    /// wand). A removed case is a compile error instead.
    private static let chromeTheme = Theme.catppuccinMocha
    private static func chromePalette() -> ResolvedPalette {
        // forceDark: the theme is dark, so pin NSTextView selection / find
        // bar / scroller system chrome dark (successor of the old .darkAqua
        // forcing).
        resolve(chromeTheme.spec, forceDark: true)
    }

    /// The HUD-mode corner radius — about a macOS notification banner's.
    private static let hudCornerRadius: CGFloat = 10

    public init(text: String, args: Args,
                onDismiss: @escaping @MainActor () -> Void) {
        self.args = args
        self.text = text
        self.onDismiss = onDismiss
        let palette = Self.chromePalette()
        // Before rendering: MarkdownRenderer reads the highlighter at render
        // time. `--no-highlight` never boots Highlightr (the JSCore start is
        // the slow part).
        MarkdownRenderer.configureSyntaxHighlighter(
            theme: args.theme ?? Defaults.theme, enabled: !args.noHighlight)
        let fontSize = CGFloat(args.fontSize ?? Defaults.fontSize)
        let attributed = Self.renderAttributed(
            text: text, markdown: args.markdown, fontSize: fontSize,
            palette: palette)
        let frame = Self.frame(for: attributed, args: args)
        panel = Self.makePanel(frame: frame, args: args, palette: palette)
        panel.contentView = Self.makeContent(
            attributed: attributed, frame: frame, fontSize: fontSize,
            palette: palette, hud: args.hud)
    }

    /// AppKit measures the text here; PanelGeometry (GlanceCore, tested)
    /// decides everything after that.
    private static func frame(for attributed: NSAttributedString,
                              args: Args) -> NSRect {
        let w = CGFloat(args.width ?? Defaults.width)
        let textWidth = w - bodyTextInset.width * 2
        let naturalTextHeight = attributed.boundingRect(
            with: NSSize(width: textWidth,
                         height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        let h = PanelGeometry.height(
            naturalTextHeight: naturalTextHeight,
            requested: args.height.map { CGFloat($0) },
            hud: args.hud)
        return PanelGeometry.frame(
            size: NSSize(width: w, height: h),
            anchor: args.at,
            visibleFrame: NSScreen.main?.visibleFrame)
    }

    private static func chromeBackground(_ palette: ResolvedPalette) -> NSColor {
        palette.background ?? NSColor(white: 0.118, alpha: 1)
    }

    /// The NSPanel itself: non-activating, floating, transient; HUD drops
    /// the title bar and goes transparent so the root's rounded layer shows.
    private static func makePanel(frame: NSRect, args: Args,
                                  palette: ResolvedPalette) -> NSPanel {
        let isHud = args.hud
        let styleMask: NSWindow.StyleMask = isHud
            ? [.nonactivatingPanel, .borderless]
            : [.nonactivatingPanel, .titled, .closable, .resizable]
        let panel = NSPanel(
            contentRect: frame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false)
        if !isHud {
            panel.title = args.title
        }
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces,
                                    .fullScreenAuxiliary,
                                    .transient]
        panel.isMovableByWindowBackground = true
        if palette.forceDarkAqua {
            panel.appearance = NSAppearance(named: .darkAqua)
        }
        if isHud {
            panel.isOpaque = false
            panel.backgroundColor = .clear
        } else {
            panel.isOpaque = true
            panel.backgroundColor = chromeBackground(palette)
        }
        panel.alphaValue = 0  // for the fade-in (present interpolates to 1)
        return panel
    }

    private static func makeContent(attributed: NSAttributedString,
                                    frame: NSRect, fontSize: CGFloat,
                                    palette: ResolvedPalette,
                                    hud: Bool) -> NSView {
        // A layer background never tracks appearance changes, so it gets the
        // concrete chrome color, not windowBackgroundColor (which would bake
        // in whatever app appearance was current at launch, often light).
        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        root.autoresizingMask = [.width, .height]
        root.wantsLayer = true
        root.layer?.backgroundColor = chromeBackground(palette).cgColor
        if hud {
            root.layer?.cornerRadius = hudCornerRadius
            root.layer?.masksToBounds = true
        }

        // Transparent, so the root's fixed dark shows through.
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
        textView.textContainerInset = bodyTextInset
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
        return root
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

    /// Typography from ViewerPanel's constants, colors from the resolved
    /// palette. The overlays are sill `ink` tiers of `foreground` rather
    /// than hand-picked white alphas, so they track the theme.
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


    /// Show the panel. It orders front without `makeKey`, so the original
    /// app keeps keyboard focus. Under `--copy` the shown text also goes to
    /// the pasteboard (for the paste-the-translation-later flow).
    public func present() {
        log.debug("present: frame=\(panel.frame) sticky=\(args.sticky) "
            + "autoClose=\(args.autoCloseSeconds.map { String($0) } ?? "off") copy=\(args.copy)")
        if args.copy {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeDuration
            panel.animator().alphaValue = 1
        }

        // Close on a click outside the panel. Deliberately not installed
        // under `--sticky` — Esc / ⌘W / the X button become the only
        // dismiss paths.
        if !args.sticky {
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

        // parseArgs rejects --sticky with --auto-close, so no second guard.
        if let seconds = args.autoCloseSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                [weak self] in self?.dismiss()
            }
        }
    }

    private func dismiss() {
        log.debug("dismiss")
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }
        if let m = keyDownMonitor {
            NSEvent.removeMonitor(m)
            keyDownMonitor = nil
        }
        // Fade out, then close + hand off. An immediate close blinks out.
        // The hand-off rides a timer, not the animation's completionHandler:
        // with the display asleep Core Animation never completes, and the
        // process lived until killed (measured 2026-09-05: `--auto-close 1`
        // logged dismiss at 1 s and was still alive 60 s later; awake, the
        // same run exits in 1.3 s). The GCD timer fires either way.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDuration) {
            [panel, onDismiss] in
            panel.close()
            onDismiss()
        }
    }
}
