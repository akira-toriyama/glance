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
    private var escMonitor: Any?
    private var keyDownMonitor: Any?

    /// markdown=true は NSAttributedString(markdown:) で rich render。失敗時は
    /// plain text に fallback (例: macOS 12 未満 / parse エラー)。
    public init(text: String, args: Args) {
        let defaultWidth: CGFloat = 380
        let defaultHeight: CGFloat = 240
        let w = args.width.map { CGFloat($0) } ?? defaultWidth
        let h = args.height.map { CGFloat($0) } ?? defaultHeight

        // アンカーがメニュー左上に来るよう、--at 指定が無ければ画面中央。
        let frame: NSRect
        if let ax = args.atX, let ay = args.atY {
            // Cocoa 座標 (Y は下から上)。アンカー = panel 左上端、panel は
            // そこから下方向に展開するので Y - h で実描画 frame を出す。
            frame = NSRect(x: CGFloat(ax), y: CGFloat(ay) - h,
                           width: w, height: h)
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            frame = NSRect(x: f.midX - w / 2, y: f.midY - h / 2,
                           width: w, height: h)
        } else {
            frame = NSRect(x: 200, y: 200, width: w, height: h)
        }

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

        // contentView: scrollable NSTextView。背景は半透明 dark vibrancy で
        // "overlay っぽさ" を出す。テーマは macOS の Dark / Light に追従。
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
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.usesFindBar = true

        if args.markdown,
           let attr = try? NSAttributedString(
            markdown: text,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            textView.textStorage?.setAttributedString(attr)
            // NSAttributedString(markdown:) の foreground は applicable な場合
            // ハードコードされていることがあるので labelColor で上書き。
            textView.textStorage?.addAttribute(
                .foregroundColor, value: NSColor.labelColor,
                range: NSRange(location: 0,
                               length: textView.textStorage?.length ?? 0))
        } else {
            textView.string = text
        }

        scroll.documentView = textView
        panel.contentView = scroll
    }

    /// panel を表示。`makeKey` せず order front するので元のアプリの
    /// キーボードフォーカスは残ったまま。
    public func present(autoCloseSeconds: Double?) {
        panel.orderFrontRegardless()

        // panel 外クリックで close。global monitor は他アプリの click を見る。
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown,
                       .otherMouseDown]) { [weak self] _ in
            self?.dismiss()
        }

        // panel 内のキー入力で Esc を拾う (panel は key になりうる
        // = becomesKeyOnlyIfNeeded で textView click 時のみ key になる)。
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown) { [weak self] ev in
            if ev.keyCode == 53 {   // Esc
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
        panel.close()
        NSApplication.shared.terminate(nil)
    }
}
