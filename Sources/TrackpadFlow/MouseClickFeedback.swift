import AppKit
import QuartzCore

final class MouseClickFeedbackController: NSObject, @unchecked Sendable {
    private let feedbackSize = CGSize(width: 72, height: 72)
    // Reuse one tiny non-activating panel. Creating and destroying an AppKit
    // window for every click causes avoidable allocations and WindowServer
    // work during rapid interaction.
    private var panel: NSPanel?
    private var feedbackView: MouseClickFeedbackView?
    private var presentationID = 0
    private var lastPresentedAt = Date.distantPast
    private var lastPresentedPoint = NSPoint.zero

    @MainActor
    func show(at screenPoint: NSPoint) {
        present(at: screenPoint)
    }

    @MainActor
    private func present(at screenPoint: NSPoint) {
        let now = Date()
        let pointDistance = hypot(
            screenPoint.x - lastPresentedPoint.x,
            screenPoint.y - lastPresentedPoint.y
        )

        // Ignore only an immediate duplicate at the same point. A real
        // double-click is slower than this window and remains visible.
        guard now.timeIntervalSince(lastPresentedAt) > 0.03 || pointDistance > 2 else {
            return
        }
        lastPresentedAt = now
        lastPresentedPoint = screenPoint

        let frame = NSRect(
            x: screenPoint.x - feedbackSize.width / 2,
            y: screenPoint.y - feedbackSize.height / 2,
            width: feedbackSize.width,
            height: feedbackSize.height
        ).integral

        if panel == nil || feedbackView == nil {
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
            let newFeedbackView = MouseClickFeedbackView(
                frame: NSRect(origin: .zero, size: frame.size)
            )
            newPanel.contentView = newFeedbackView
            panel = newPanel
            feedbackView = newFeedbackView
        }

        guard let panel, let feedbackView else { return }
        presentationID &+= 1
        let currentPresentationID = presentationID
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        let duration = feedbackView.play()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) { @MainActor [weak self, weak panel] in
            guard let self,
                  self.presentationID == currentPresentationID,
                  let panel else { return }
            panel.orderOut(nil)
        }
    }
}

@MainActor
private final class MouseClickFeedbackView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func play() -> TimeInterval {
        guard let rootLayer = layer else { return 0 }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let reduceForPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let useReducedAnimation = reduceMotion || reduceForPower
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let endRadius: CGFloat = 26

        rootLayer.removeAllAnimations()
        rootLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        // Keep the feedback entirely in Core Animation. In particular, do
        // not use NSVisualEffectView/.behindWindow here: backdrop blur is the
        // most expensive part of this short-lived effect.
        let fill = addRippleFill(to: rootLayer, center: center, radius: endRadius)

        return animate(
            fill: fill,
            center: center,
            endRadius: endRadius,
            reduceMotion: useReducedAnimation
        )
    }

    private func addRippleFill(
        to rootLayer: CALayer,
        center: CGPoint,
        radius: CGFloat
    ) -> CAShapeLayer {
        let fill = CAShapeLayer()
        fill.frame = bounds
        fill.path = circularRipplePath(center: center, radius: radius)
        // A translucent solid face gives the ripple the visual weight of
        // frosted glass without requiring backdrop blur.
        fill.fillColor = NSColor.white.withAlphaComponent(0.24).cgColor
        fill.strokeColor = NSColor.clear.cgColor
        rootLayer.addSublayer(fill)
        return fill
    }

    private func animate(
        fill: CAShapeLayer,
        center: CGPoint,
        endRadius: CGFloat,
        reduceMotion: Bool
    ) -> TimeInterval {
        let duration: TimeInterval = reduceMotion ? 0.18 : 0.48
        let startRadius: CGFloat = reduceMotion ? 20 : 4
        let middleRadius = reduceMotion ? endRadius : 14

        let ripplePath = CAKeyframeAnimation(keyPath: "path")
        ripplePath.values = reduceMotion
            ? [
                circularRipplePath(center: center, radius: startRadius),
                circularRipplePath(center: center, radius: endRadius)
            ]
            : [
                circularRipplePath(center: center, radius: startRadius),
                circularRipplePath(center: center, radius: middleRadius),
                circularRipplePath(center: center, radius: endRadius)
            ]
        ripplePath.keyTimes = reduceMotion ? [0, 1] : [0, 0.56, 1]
        ripplePath.calculationMode = .cubic
        ripplePath.duration = duration
        fill.add(ripplePath, forKey: "centered-cas-ripple-fill")

        let fillOpacity = CAKeyframeAnimation(keyPath: "opacity")
        fillOpacity.values = reduceMotion
            ? [0, 0.72, 0]
            : [0, 0.92, 0.34, 0]
        fillOpacity.keyTimes = reduceMotion
            ? [0, 0.3, 1]
            : [0, 0.12, 0.68, 1]
        fillOpacity.calculationMode = .linear
        fill.opacity = 0
        fill.add(fillOpacity, forKey: "centered-cas-ripple-fill-opacity")
        return duration
    }

    private func circularRipplePath(center: CGPoint, radius: CGFloat) -> CGPath {
        CGPath(
            ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ),
            transform: nil
        )
    }
}
