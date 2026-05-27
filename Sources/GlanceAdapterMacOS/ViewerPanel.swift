import AppKit
import GlanceCore

/// 入力テキストを native NSPanel に表示する viewer。**focus を奪わない** ことが
/// 設計の核 — `.nonactivatingPanel` style + `becomesKeyOnlyIfNeeded` で実現する。
///
/// 表示後は user の dismiss (Esc / panel 外クリック) で `NSApp.terminate(nil)`
/// が呼ばれる前提。auto-close 指定があれば一定時間後に自滅。
@MainActor
public final class ViewerPanel {
    private let panel: NSPanel
    private var clickOutsideMonitor: Any?
    private var keyDownMonitor: Any?

    /// fade-in/out 時間。短すぎると pop に見え、長すぎると mousing と被る。
    /// macOS 通知センターの 0.15s 前後に合わせる。
    private static let fadeDuration: TimeInterval = 0.14

    /// 本文ベースフォントサイズの既定値。`--font-size` 指定時はそちらが勝つ。
    /// 16pt は macOS 標準 body (13pt) より一回り大きく "ちらっと見る" 用途に
    /// 適した値。MarkdownRenderer.Style.baseFontSize として渡され、見出し階層は
    /// そこから倍率で派生する。
    private static let defaultBaseFontSize: CGFloat = 16

    /// 行間 / 余白 / block-level 装飾の constants。MacDown GitHub2.css 等の
    /// 値を踏襲しつつ、native NSAttributedString に翻訳したもの。
    private static let bodyLineSpacing: CGFloat = 4
    private static let bodyTextInset = NSSize(width: 18, height: 14)
    private static let codeBlockIndent: CGFloat = 10
    private static let codeBlockParagraphSpacing: CGFloat = 6
    private static let blockquoteIndent: CGFloat = 16

    /// solid #1E1E1E 背景の上でちゃんと見える濃さ。darkAqua 強制なので
    /// dynamicProvider は不要 (light variant 値は使われない)。
    /// alpha は panel bg #1E1E1E (white 0.118) との混色結果で決めている。
    private static let inlineCodeBackground =
        NSColor(white: 1.0, alpha: 0.22)
    private static let codeBlockBackground =
        NSColor(white: 1.0, alpha: 0.18)

    /// HUD モードの角丸半径。macOS の通知バナーと同程度。
    private static let hudCornerRadius: CGFloat = 10

    public init(text: String, args: Args) {
        // CLI から syntax highlighter を構成。`--no-highlight` 時は Highlightr
        // 自体を起動しない (JSCore 起動 ~30-100ms を skip)。
        MarkdownRenderer.configureSyntaxHighlighter(
            theme: args.theme, enabled: !args.noHighlight)

        let fontSize = args.fontSize.map { CGFloat($0) }
            ?? Self.defaultBaseFontSize
        let isHud = args.hud

        let defaultWidth: CGFloat = 380
        let w = args.width.map { CGFloat($0) } ?? defaultWidth
        let requestedH = args.height.map { CGFloat($0) }

        // contentView を組み立ててから text の自然高さで panel 高さを決める。
        // ユーザが --height で明示した場合はそれを尊重 (clamp なし)。
        let textInset = Self.bodyTextInset
        let attributed = Self.renderAttributed(
            text: text, markdown: args.markdown, fontSize: fontSize)

        let contentWidth = w
        let textWidth = contentWidth - textInset.width * 2
        let naturalTextHeight = attributed.boundingRect(
            with: NSSize(width: textWidth,
                         height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        // HUD は title bar が無いので slack を引かない。
        let titleBarSlack: CGFloat = isHud ? 0 : 28
        let naturalPanelHeight = ceil(naturalTextHeight)
            + textInset.height * 2
            + titleBarSlack
        let minH: CGFloat = isHud ? 40 : 80
        let maxH: CGFloat = 600
        let autoH = min(max(naturalPanelHeight, minH), maxH)
        let h = requestedH ?? autoH

        // アンカーがメニュー左上に来るよう、--at 指定が無ければ画面中央。
        // 画面端ギリギリの座標を渡されても panel がはみ出ないように clamp する。
        let frame: NSRect = {
            let baseRect: NSRect
            if let ax = args.atX, let ay = args.atY {
                // Cocoa 座標 (Y は下から上)。アンカー = panel 左上端、panel は
                // そこから下方向に展開するので Y - h で実描画 frame を出す。
                baseRect = NSRect(x: CGFloat(ax),
                                  y: CGFloat(ay) - h,
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
        // VSCode / Xcode の dark theme と同じ硬めの dark gray 背景。
        // HUD モードは panel 自体は透明にして root の rounded layer で
        // 角丸付き dark を表示する。それ以外は panel が直接 #1E1E1E。
        panel.appearance = NSAppearance(named: .darkAqua)
        if isHud {
            panel.isOpaque = false
            panel.backgroundColor = .clear
        } else {
            panel.isOpaque = true
            panel.backgroundColor = NSColor(white: 0.118, alpha: 1)
        }
        panel.hasShadow = true
        panel.alphaValue = 0  // fade-in 用 (present で 1 へ補間)

        // root: ハードコード dark RGB。layer bg は appearance に動的追従しない
        // ので windowBackgroundColor を入れると現在の app appearance (起動時は
        // light な事が多い) が焼き付いて panel の darkAqua 強制と矛盾する。
        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        root.autoresizingMask = [.width, .height]
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 0.118, alpha: 1).cgColor
        if isHud {
            root.layer?.cornerRadius = Self.hudCornerRadius
            root.layer?.masksToBounds = true
        }

        // contentView: scrollable NSTextView。背景は透明にして root の dark を
        // 透かす (root が固定 dark なので結果として常に VSCode-like dark bg)。
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: frame.size))
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]

        // TextKit 1 を明示構築: GlanceLayoutManager (inline code pill 描画用)
        // を挟むため。`NSTextView(frame:)` だと内部 storage / layout を勝手に
        // 作るので、自前で stack を組んで textContainer 経由で渡す。NSTextTable
        // も TextKit 1 で動くので code block / table はそのまま機能する。
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
        textView.textColor = .labelColor
        textView.usesFindBar = true

        textView.textStorage?.setAttributedString(attributed)
        // foregroundColor / typography は renderAttributed 内で確定済み。
        // ここで上書きすると blockquote の secondaryLabelColor 等が消えるので
        // 触らない。

        scroll.documentView = textView
        // 階層: panel.contentView = root (solid dark, 角丸 in HUD) → scroll
        // → textView。
        root.addSubview(scroll)
        panel.contentView = root
    }

    /// markdown=true は swift-markdown でパースして MarkdownRenderer に投げる。
    /// 非 markdown は plain text を line-spacing 付き attributed に。
    private static func renderAttributed(text: String,
                                         markdown: Bool,
                                         fontSize: CGFloat) -> NSAttributedString {
        if markdown {
            let renderer = MarkdownRenderer(style: rendererStyle(fontSize: fontSize))
            return renderer.render(text)
        }
        let p = NSMutableParagraphStyle()
        p.lineSpacing = bodyLineSpacing
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: p,
        ])
    }

    /// MarkdownRenderer に渡す Style。ViewerPanel の typography constants を
    /// そのまま流し込むだけ。
    private static func rendererStyle(fontSize: CGFloat) -> MarkdownRenderer.Style {
        MarkdownRenderer.Style(
            baseFontSize: fontSize,
            bodyLineSpacing: bodyLineSpacing,
            inlineCodeBackground: inlineCodeBackground,
            codeBlockBackground: codeBlockBackground,
            codeBlockIndent: codeBlockIndent,
            blockquoteIndent: blockquoteIndent,
            codeBlockParagraphSpacing: codeBlockParagraphSpacing)
    }

    /// `--at` 指定が画面端にめり込んだ場合に visibleFrame 内へ寄せる。
    /// 上流 pipeline (eventfx の selection 座標) が画面右端に近い時に有効。
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

    /// panel を表示。`makeKey` せず order front するので元のアプリの
    /// キーボードフォーカスは残ったまま。`copy=true` なら表示内容を
    /// pbcopy にも流す (翻訳結果を後で paste するフロー向け)。
    public func present(autoCloseSeconds: Double?, copy: Bool = false,
                        copyText: String = "") {
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

        // panel 外クリックで close。global monitor は他アプリの click を見る。
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown,
                       .otherMouseDown]) { [weak self] _ in
            self?.dismiss()
        }

        // panel 内のキー入力で Esc / ⌘W を拾う (panel は key になりうる
        // = becomesKeyOnlyIfNeeded で textView click 時のみ key になる)。
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown) { [weak self] ev in
            if ev.keyCode == 53 {   // Esc
                self?.dismiss()
                return nil
            }
            // ⌘W は macOS で "閉じる" の慣習キー。Esc を取り逃した時の保険。
            if ev.modifierFlags.contains(.command),
               ev.charactersIgnoringModifiers == "w" {
                self?.dismiss()
                return nil
            }
            return ev
        }

        if let seconds = autoCloseSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                [weak self] in self?.dismiss()
            }
        }
    }

    private func dismiss() {
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }
        if let m = keyDownMonitor {
            NSEvent.removeMonitor(m)
            keyDownMonitor = nil
        }
        // fade-out してから close + terminate。close 即時だと "パッ" と消える。
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            self.panel.close()
            NSApplication.shared.terminate(nil)
        })
    }
}
