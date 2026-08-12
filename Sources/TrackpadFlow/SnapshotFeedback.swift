import AppKit

final class SnapshotFeedbackController: NSObject, @unchecked Sendable {
    enum Kind {
        case saved
        case restored
        case saveFailed
        case restoreFailed

        var title: String {
            switch self {
            case .saved: return "工作场景已保持"
            case .restored: return "工作场景已恢复"
            case .saveFailed: return "工作场景保持失败"
            case .restoreFailed: return "工作场景恢复失败"
            }
        }

        var symbolName: String {
            switch self {
            case .saved: return "square.and.arrow.down.fill"
            case .restored: return "arrow.clockwise.circle.fill"
            case .saveFailed, .restoreFailed: return "exclamationmark.triangle.fill"
            }
        }

        var tint: NSColor {
            switch self {
            case .saved, .restored: return .systemBlue
            case .saveFailed, .restoreFailed: return .systemOrange
            }
        }
    }

    private var panel: NSPanel?
    private var presentationID = 0

    func show(kind: Kind, detail: String) {
        // The event tap callback is synchronous and may arrive off the main
        // actor. Keep the UI hop deliberately small and avoid capturing a
        // DispatchWorkItem here; AppKit feedback must never be able to take
        // down the gesture monitor after a valid snapshot gesture.
        DispatchQueue.main.async { [weak self] in
            self?.present(kind: kind, detail: detail)
        }
    }

    @MainActor
    private func present(kind: Kind, detail: String) {
        presentationID &+= 1
        let currentPresentationID = presentationID
        panel?.orderOut(nil)

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ??
            NSScreen.main ??
            NSScreen.screens.first
        guard let screen else { return }

        let size = CGSize(width: 330, height: 66)
        let visibleFrame = screen.visibleFrame
        let frame = NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 24,
            width: size.width,
            height: size.height
        ).integral

        let newPanel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.hidesOnDeactivate = false
        newPanel.ignoresMouseEvents = true
        newPanel.level = .statusBar
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        newPanel.contentView = SnapshotFeedbackView(
            frame: NSRect(origin: .zero, size: size),
            kind: kind,
            detail: detail
        )
        newPanel.alphaValue = 1
        panel = newPanel
        newPanel.orderFrontRegardless()

        // A generation token makes repeated gestures safe without retaining
        // cancellable work items. The newest toast owns the visible panel;
        // an older delayed cleanup simply becomes a no-op.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self, weak newPanel] in
            guard let self,
                  self.presentationID == currentPresentationID,
                  let newPanel else { return }
            newPanel.orderOut(nil)
            if self.panel === newPanel {
                self.panel = nil
            }
        }
    }
}

@MainActor
private final class SnapshotFeedbackView: NSView {
    private let kind: SnapshotFeedbackController.Kind
    private let detail: String

    init(
        frame frameRect: NSRect,
        kind: SnapshotFeedbackController.Kind,
        detail: String
    ) {
        self.kind = kind
        self.detail = detail
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let cardRect = bounds.insetBy(dx: 1, dy: 1)
        let card = NSBezierPath(roundedRect: cardRect, xRadius: 15, yRadius: 15)
        NSColor(calibratedWhite: 0.08, alpha: 0.94).setFill()
        card.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        card.lineWidth = 1
        card.stroke()

        let iconRect = NSRect(x: 17, y: 19, width: 27, height: 27)
        if let image = NSImage(
            systemSymbolName: kind.symbolName,
            accessibilityDescription: kind.title
        ) {
            image.isTemplate = false
            kind.tint.set()
            image.draw(in: iconRect)
        }

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.white.withAlphaComponent(0.62)
        ]
        (kind.title as NSString).draw(
            at: NSPoint(x: 57, y: 36),
            withAttributes: titleAttributes
        )
        (detail as NSString).draw(
            at: NSPoint(x: 57, y: 19),
            withAttributes: detailAttributes
        )
    }
}
