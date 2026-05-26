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

    /// markdown=true は NSAttributedString(markdown:) で rich render。失敗時は
    /// plain text に fallback (例: parse エラー)。block-level (見出し / リスト /
    /// code block) も描画する `.full` を使う。
    public init(text: String, args: Args) {
        let defaultWidth: CGFloat = 380
        let w = args.width.map { CGFloat($0) } ?? defaultWidth
        let requestedH = args.height.map { CGFloat($0) }

        // contentView を組み立ててから text の自然高さで panel 高さを決める。
        // ユーザが --height で明示した場合はそれを尊重 (clamp なし)。
        let textInset = NSSize(width: 12, height: 10)
        let attributed = Self.renderAttributed(text: text, markdown: args.markdown)

        let contentWidth = w
        let textWidth = contentWidth - textInset.width * 2
        let naturalTextHeight = attributed.boundingRect(
            with: NSSize(width: textWidth,
                         height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        let titleBarSlack: CGFloat = 28  // titled chrome 分の概算
        let naturalPanelHeight = ceil(naturalTextHeight)
            + textInset.height * 2
            + titleBarSlack
        let minH: CGFloat = 80
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

        panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .titled, .closable,
                        .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.title = args.title
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces,
                                    .fullScreenAuxiliary,
                                    .transient]
        panel.isMovableByWindowBackground = true
        // panel 自体は透明にして、後ろの NSVisualEffectView が見えるようにする。
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.alphaValue = 0  // fade-in 用 (present で 1 へ補間)

        // root: NSVisualEffectView (HUD / popover material) でフォーカスを奪わ
        // ない overlay 感を出す。Spotlight / 通知センターと同じ磨りガラス。
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero,
                                                    size: frame.size))
        blur.autoresizingMask = [.width, .height]
        blur.blendingMode = .behindWindow
        blur.material = .hudWindow
        blur.state = .active

        // contentView: scrollable NSTextView。背景は透明にして blur を透かす。
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: frame.size))
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: scroll.bounds)
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = textInset
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.usesFindBar = true

        textView.textStorage?.setAttributedString(attributed)
        // NSAttributedString(markdown:) の foreground は applicable な場合
        // ハードコードされていることがあるので labelColor で上書き。
        textView.textStorage?.addAttribute(
            .foregroundColor, value: NSColor.labelColor,
            range: NSRange(location: 0,
                           length: textView.textStorage?.length ?? 0))

        scroll.documentView = textView
        blur.addSubview(scroll)
        panel.contentView = blur
    }

    /// markdown=true なら block-level も含めて attributed 化、失敗 / 非 markdown
    /// は plain text を attributed 化して返す。auto-size の高さ計算で使うため、
    /// init の最序盤で 1 度だけ呼ぶ。
    private static func renderAttributed(text: String,
                                         markdown: Bool) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 14)
        if markdown,
           let attr = try? NSAttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .full)) {
            return attr
        }
        return NSAttributedString(
            string: text,
            attributes: [.font: font,
                         .foregroundColor: NSColor.labelColor])
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
