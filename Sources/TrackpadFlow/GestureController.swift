import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

final class GestureController: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var isMonitoring = false
    @Published private(set) var permissionRequestSent = false
    @Published private(set) var lastAction = "等待 Command + 横向触控板手势"
    @Published private(set) var isEndpointSelectionWaiting = false
    @Published var clickFeedbackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(clickFeedbackEnabled, forKey: Self.clickFeedbackEnabledKey)
            let previouslyNeededMouseEvents = oldValue || endpointSelectionEnabled
            if previouslyNeededMouseEvents != needsMouseEvents {
                reconfigureEventTap()
            }
        }
    }
    @Published var endpointSelectionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(endpointSelectionEnabled, forKey: Self.endpointSelectionEnabledKey)
            resetEndpointSelectionState()
            let previouslyNeededMouseEvents = clickFeedbackEnabled || oldValue
            if previouslyNeededMouseEvents != needsMouseEvents {
                reconfigureEventTap()
            }
        }
    }
    @Published var endpointDoubleTapWindow: Double {
        didSet {
            UserDefaults.standard.set(endpointDoubleTapWindow, forKey: Self.endpointDoubleTapWindowKey)
            resetEndpointSelectionState()
        }
    }
    @Published var directionInverted: Bool {
        didSet {
            UserDefaults.standard.set(directionInverted, forKey: Self.directionInvertedKey)
        }
    }
    @Published var triggerThreshold: Double {
        didSet {
            UserDefaults.standard.set(triggerThreshold, forKey: Self.triggerThresholdKey)
        }
    }

    private static let directionInvertedKey = "directionInverted"
    private static let triggerThresholdKey = "triggerThreshold"
    private static let clickFeedbackEnabledKey = "clickFeedbackEnabled"
    private static let endpointSelectionEnabledKey = "endpointSelectionEnabled"
    private static let endpointDoubleTapWindowKey = "endpointDoubleTapWindow"
    private static let defaultTriggerThreshold = 72.0
    private static let defaultEndpointDoubleTapWindow = 0.65
    static let minimumEndpointDoubleTapWindow = 0.30
    static let maximumEndpointDoubleTapWindow = 3.00
    private static let lightTapMaximumDuration: TimeInterval = 0.22
    private static let tapDistanceTolerance: CGFloat = 40
    private static let endpointSnapRadius: CGFloat = 24
    private static let endpointSnapStep: CGFloat = 6
    // 给小幅度、较慢的左滑更多累计时间；触发后仍由冷却保护避免重复动作。
    private static let gestureTimeout: TimeInterval = 0.32
    // Command 松开后保留很短的手势尾部，避免释放时正好丢掉最后几个
    // 触控板采样；这不是长按要求，只是完成已经开始的手势。
    private static let commandReleaseGrace: TimeInterval = 0.6
    private static let gestureEndDebounce: TimeInterval = 0.45
    private static let eventActionCooldown: TimeInterval = 0.3
    private static let minimumSnapshotTriggerThreshold: CGFloat = 24
    private static let maximumPermissionPollingTicks = 120

    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var permissionPollingTicks = 0
    private var resetWorkItem: DispatchWorkItem?
    private var horizontalDistance: CGFloat = 0
    private var verticalDistance: CGFloat = 0
    private var gestureStartedAt = Date.distantPast
    private var gestureHasTriggered = false
    private var commandGestureActive = false
    private var commandModifierHeld = false
    private var leftCommandKeyDown = false
    private var rightCommandKeyDown = false
    private var commandReleasedAt = Date.distantPast
    private var actionInProgress = false
    private var gestureEndWorkItem: DispatchWorkItem?
    private var ignoreEventsUntil = Date.distantPast
    private var endpointLastTapUpAt = Date.distantPast
    private var endpointLastTapPoint = CGPoint.zero
    private var endpointTapDownAt = Date.distantPast
    private var endpointTapDownPoint = CGPoint.zero
    private var endpointTapMoved = false
    private var endpointDoubleTapCandidate = false
    private var endpointStartPoint = CGPoint.zero
    // The first destination click is buffered only until a matching second
    // click confirms the endpoint. This preserves the original selection
    // anchor for a reliable Shift-click across long, scrolled content.
    private var endpointPendingDown: CGEvent?
    private var endpointPendingUp: CGEvent?
    private var endpointPendingSecondDown: CGEvent?
    private var endpointPendingSecondUp: CGEvent?
    private var endpointPendingTapPoint = CGPoint.zero
    private var endpointPendingTapAt = Date.distantPast
    private var endpointPendingWorkItem: DispatchWorkItem?
    private var endpointReplayingEvents = false
    private let mouseClickFeedback = MouseClickFeedbackController()
    private let snapshotFeedback = SnapshotFeedbackController()

    override init() {
        directionInverted = UserDefaults.standard.bool(forKey: Self.directionInvertedKey)
        let savedThreshold = UserDefaults.standard.double(forKey: Self.triggerThresholdKey)
        triggerThreshold = savedThreshold > 0 ? savedThreshold : Self.defaultTriggerThreshold
        clickFeedbackEnabled = UserDefaults.standard.object(forKey: Self.clickFeedbackEnabledKey) as? Bool ?? true
        endpointSelectionEnabled = UserDefaults.standard.object(forKey: Self.endpointSelectionEnabledKey) as? Bool ?? true
        let savedEndpointWindow = UserDefaults.standard.double(forKey: Self.endpointDoubleTapWindowKey)
        endpointDoubleTapWindow = savedEndpointWindow > 0
            ? min(
                max(savedEndpointWindow, Self.minimumEndpointDoubleTapWindow),
                Self.maximumEndpointDoubleTapWindow
            )
            : Self.defaultEndpointDoubleTapWindow
        super.init()

        accessibilityTrusted = AXIsProcessTrusted()
        commandModifierHeld = CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
        // Mouse movement is only needed after the second light tap is
        // confirmed. Keeping it out of the idle event mask avoids receiving
        // every cursor sample while the app is doing nothing.
        installEventTap()

        // Do not surprise first-launch users with an unsolicited system
        // prompt or poll forever before they choose to grant access. If AX is
        // already trusted but the Event Tap is unavailable, polling remains
        // useful while the user enables Input Monitoring.
        if accessibilityTrusted && eventTap == nil {
            startPermissionPollingIfNeeded()
        }
    }

    deinit {
        permissionTimer?.invalidate()
        resetWorkItem?.cancel()
        gestureEndWorkItem?.cancel()
        endpointPendingWorkItem?.cancel()

        if let eventSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
    }

    var directionDescription: String {
        if directionInverted {
            return "当前已反转：Command + 右滑恢复栈顶窗口，Command + 左滑最小化"
        }
        return "Command + 右滑最小化当前窗口，Command + 左滑恢复栈顶窗口"
    }

    func refreshPermission() {
        accessibilityTrusted = AXIsProcessTrusted()
        if accessibilityTrusted {
            permissionRequestSent = false
        }
        // Input Monitoring may be granted after the app starts. Retrying here
        // lets the toggle take effect without requiring another app restart.
        if eventTap == nil {
            installEventTap()
        }

        // Once the event tap is alive and Accessibility is trusted, there is
        // no reason to wake the main run loop every second forever.
        if accessibilityTrusted && eventTap != nil {
            permissionTimer?.invalidate()
            permissionTimer = nil
            permissionPollingTicks = 0
        }
    }

    @objc private func refreshPermissionTimer() {
        refreshPermission()
        guard permissionTimer != nil else { return }

        permissionPollingTicks += 1
        if permissionPollingTicks >= Self.maximumPermissionPollingTicks {
            permissionTimer?.invalidate()
            permissionTimer = nil
            permissionPollingTicks = 0
            permissionRequestSent = false
            lastAction = "权限请求尚未完成；需要时可再次点击申请按钮"
        }
    }

    func requestAccessibilityPermission() {
        refreshPermission()
        guard !accessibilityTrusted else {
            lastAction = "辅助功能权限已开启"
            return
        }

        permissionRequestSent = true
        lastAction = "已向 macOS 发出辅助功能请求；请在系统设置中开启 TrackpadFlow"
        _ = requestSystemPermissionPrompt()
        startPermissionPollingIfNeeded()
        openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    func openInputMonitoringSettings() {
        startPermissionPollingIfNeeded()
        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    @discardableResult
    private func requestSystemPermissionPrompt() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        return accessibilityTrusted
    }

    private func startPermissionPollingIfNeeded() {
        guard permissionTimer == nil else { return }
        permissionPollingTicks = 0
        permissionTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(refreshPermissionTimer),
            userInfo: nil,
            repeats: true
        )
    }

    private func installEventTap() {
        guard eventTap == nil else { return }

        var eventMask: CGEventMask = 0
        eventMask |= CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        eventMask |= CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        // flagsChanged is normally sufficient, but some app/trackpad paths
        // deliver the first scroll sample before that state reaches this tap.
        // Keep keyDown/keyUp as a reliability fallback and filter immediately
        // by the two Command key codes in the callback.
        eventMask |= CGEventMask(1 << CGEventType.keyDown.rawValue)
        eventMask |= CGEventMask(1 << CGEventType.keyUp.rawValue)
        if needsMouseEvents {
            eventMask |= CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            eventMask |= CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: context
        ) else {
            isMonitoring = false
            return
        }

        guard let eventSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            CFMachPortInvalidate(eventTap)
            isMonitoring = false
            return
        }

        self.eventTap = eventTap
        self.eventSource = eventSource
        CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isMonitoring = true
    }

    private var needsMouseEvents: Bool {
        clickFeedbackEnabled || endpointSelectionEnabled
    }

    private func reconfigureEventTap() {
        removeEventTap()
        installEventTap()
    }

    private func removeEventTap() {
        if let eventSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        eventSource = nil
        eventTap = nil
        isMonitoring = false
    }

    private static let eventTapCallback: CGEventTapCallBack = {
        _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<GestureController>
            .fromOpaque(refcon)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = controller.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            controller.handleFlagsChanged(event)
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown || type == .keyUp {
            controller.handleCommandKeyEvent(event, type: type)
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDown {
            guard let output = controller.handleMouseDown(event) else {
                return nil
            }
            return Unmanaged.passUnretained(output)
        }

        if type == .leftMouseUp {
            guard let output = controller.handleMouseUp(event) else {
                return nil
            }
            return Unmanaged.passUnretained(output)
        }

        guard let output = controller.handleScrollEvent(event, type: type) else {
            // Returning nil prevents the Command + horizontal event from reaching the app.
            return nil
        }
        return Unmanaged.passUnretained(output)
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isDown = event.flags.contains(.maskCommand)
        let wasHeld = commandModifierHeld
        if keyCode == 54 {
            rightCommandKeyDown = isDown
        } else if keyCode == 55 {
            leftCommandKeyDown = isDown
        }
        commandModifierHeld = leftCommandKeyDown || rightCommandKeyDown || isDown
        if commandModifierHeld {
            commandReleasedAt = .distantPast
        } else if wasHeld {
            commandReleasedAt = Date()
            if commandGestureActive || gestureHasTriggered {
                scheduleGestureReset(after: Self.commandReleaseGrace)
            }
        }
    }

    private func handleCommandKeyEvent(_ event: CGEvent, type: CGEventType) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 54 || keyCode == 55 else { return }

        let isDown = type == .keyDown
        let wasHeld = commandModifierHeld
        if keyCode == 54 {
            rightCommandKeyDown = isDown
        } else {
            leftCommandKeyDown = isDown
        }
        commandModifierHeld = leftCommandKeyDown || rightCommandKeyDown
        if commandModifierHeld {
            commandReleasedAt = .distantPast
        } else if wasHeld {
            commandReleasedAt = Date()
            if commandGestureActive || gestureHasTriggered {
                scheduleGestureReset(after: Self.commandReleaseGrace)
            }
        }
    }

    private func physicalCommandKeyIsDown() -> Bool {
        CGEventSource.keyState(.combinedSessionState, key: 54) ||
            CGEventSource.keyState(.combinedSessionState, key: 55)
    }

    private func commandIsHeld(for event: CGEvent) -> Bool {
        let recentlyReleased = commandGestureActive &&
            Date().timeIntervalSince(commandReleasedAt) <= Self.commandReleaseGrace
        return event.flags.contains(.maskCommand) ||
            commandModifierHeld ||
            recentlyReleased ||
            CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) ||
            NSEvent.modifierFlags.contains(.command) ||
            physicalCommandKeyIsDown()
    }

    private func handleMouseDown(_ event: CGEvent) -> CGEvent? {
        // Events posted by replayPendingEndpointClick must pass through the
        // tap untouched; otherwise the replay would be buffered again.
        if endpointReplayingEvents {
            return event
        }

        showClickFeedbackIfNeeded()

        guard endpointSelectionEnabled else {
            return event
        }

        // Finder owns repeated same-position double-clicks for opening files
        // and folders. Never arm the text endpoint state machine there.
        if frontmostApplicationIsFinder {
            resetEndpointSelectionState()
            return event
        }

        if isEndpointSelectionWaiting {
            let now = Date()
            // A second double-click in the same area is much more likely to
            // be a native open/select action than the far endpoint of a long
            // text selection. Drop endpoint mode before this click reaches
            // the app, so the whole double-click remains untouched.
            if distance(from: event.location, to: endpointStartPoint) <= Self.tapDistanceTolerance {
                cancelEndpointWaiting()
                endpointTapDownAt = now
                endpointTapDownPoint = event.location
                endpointTapMoved = false
                return event
            }

            if endpointPendingDown == nil {
                // First click at the possible destination. Hold both halves
                // until we know whether a matching second click follows.
                endpointPendingDown = copyEvent(event)
                endpointPendingUp = nil
                endpointPendingSecondDown = nil
                endpointPendingSecondUp = nil
                endpointTapDownAt = now
                endpointTapDownPoint = event.location
                endpointTapMoved = false
                return nil
            }

            let elapsed = now.timeIntervalSince(endpointPendingTapAt)
            let isSecondEndpointTap = endpointPendingUp != nil &&
                elapsed >= 0 &&
                elapsed <= self.doubleTapInterval &&
                distance(from: event.location, to: endpointPendingTapPoint) <= Self.tapDistanceTolerance

            if isSecondEndpointTap {
                // Hold the second down event too. On mouse-up we can then
                // replay the first click with Shift and swallow the second.
                endpointPendingSecondDown = copyEvent(event)
                endpointPendingWorkItem?.cancel()
                endpointPendingWorkItem = nil
                endpointTapDownAt = now
                endpointTapDownPoint = event.location
                endpointTapMoved = false
                return nil
            }

            // A different click means the pending click was only a normal
            // single click. Release it unchanged and cancel endpoint mode;
            // the new click is allowed through normally.
            replayPendingEndpointClick(withShift: false)
            cancelEndpointWaiting()
            endpointTapDownAt = now
            endpointTapDownPoint = event.location
            endpointTapMoved = false
            return event
        }

        let now = Date()
        let interval = self.doubleTapInterval
        let elapsed = now.timeIntervalSince(endpointLastTapUpAt)
        let isSecondTap = elapsed >= 0 && elapsed <= interval &&
            distance(from: event.location, to: endpointLastTapPoint) <= Self.tapDistanceTolerance

        endpointTapDownAt = now
        endpointTapDownPoint = event.location
        endpointTapMoved = false

        endpointDoubleTapCandidate = isSecondTap
        return event
    }

    private func handleMouseUp(_ event: CGEvent) -> CGEvent? {
        guard endpointSelectionEnabled else {
            return event
        }

        if endpointReplayingEvents {
            return event
        }

        if frontmostApplicationIsFinder {
            return event
        }

        let now = Date()
        let duration = now.timeIntervalSince(endpointTapDownAt)
        let isLightTap = duration >= 0 &&
            duration <= Self.lightTapMaximumDuration &&
            !endpointTapMoved &&
            distance(from: event.location, to: endpointTapDownPoint) <= Self.tapDistanceTolerance

        guard isLightTap else {
            if isEndpointSelectionWaiting {
                // The pending action was not a light click. Replay it as the
                // user's original mouse action, then leave endpoint mode.
                if endpointPendingSecondDown != nil {
                    endpointPendingSecondUp = copyEvent(event)
                } else {
                    endpointPendingUp = copyEvent(event)
                }
                replayPendingEndpointClick(withShift: false)
                cancelEndpointWaiting()
                return nil
            }
            endpointDoubleTapCandidate = false
            endpointLastTapUpAt = .distantPast
            return event
        }

        if isEndpointSelectionWaiting {
            if endpointPendingSecondDown != nil {
                // The second tap confirms the destination double-click. Use
                // the first buffered click as one Shift-click, then swallow
                // the confirming pair so selection ends immediately.
                endpointPendingSecondUp = copyEvent(event)
                let endpointPoint = endpointPendingSecondDown?.location ?? event.location
                let snappedPoint = snappedEndpointLocation(near: endpointPoint)
                replayPendingEndpointClick(
                    withShift: true,
                    includeSecondClick: false,
                    location: snappedPoint
                )
                cancelEndpointWaiting()
                lastAction = "两端双击框选已完成"
                return nil
            }

            // First destination tap: suppress it briefly. If no matching
            // second tap arrives, replay it unchanged and cancel endpoint.
            endpointPendingUp = copyEvent(event)
            endpointPendingTapPoint = event.location
            endpointPendingTapAt = now
            schedulePendingEndpointClickFlush()
            return nil
        }

        if endpointDoubleTapCandidate {
            endpointStartPoint = event.location
            endpointDoubleTapCandidate = false
            endpointLastTapUpAt = .distantPast
            isEndpointSelectionWaiting = true
            lastAction = "起点已记录；双指滚动到另一端后再次双击"
            return event
        }

        endpointLastTapUpAt = now
        endpointLastTapPoint = event.location
        return event
    }

    private func showClickFeedbackIfNeeded() {
        guard clickFeedbackEnabled else { return }

        let screenPoint = NSEvent.mouseLocation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.clickFeedbackEnabled else { return }
            self.mouseClickFeedback.show(at: screenPoint)
        }
    }

    private var doubleTapInterval: TimeInterval {
        min(
            max(endpointDoubleTapWindow, Self.minimumEndpointDoubleTapWindow),
            Self.maximumEndpointDoubleTapWindow
        )
    }

    private func schedulePendingEndpointClickFlush() {
        endpointPendingWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isEndpointSelectionWaiting else { return }
            self.replayPendingEndpointClick(withShift: false)
            self.cancelEndpointWaiting()
            self.lastAction = "普通单点已放行，端点框选已取消"
        }
        endpointPendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + self.doubleTapInterval,
            execute: workItem
        )
    }

    private func copyEvent(_ event: CGEvent) -> CGEvent {
        event.copy() ?? event
    }

    private func replayPendingEndpointClick(
        withShift: Bool,
        includeSecondClick: Bool = true,
        location: CGPoint? = nil
    ) {
        guard let firstDown = endpointPendingDown,
              let firstUp = endpointPendingUp else {
            return
        }

        endpointReplayingEvents = true
        defer { endpointReplayingEvents = false }

        postEndpointEvent(firstDown, withShift: withShift, location: location)
        postEndpointEvent(firstUp, withShift: withShift, location: location)

        if includeSecondClick,
           let secondDown = endpointPendingSecondDown,
           let secondUp = endpointPendingSecondUp {
            postEndpointEvent(secondDown, withShift: withShift, location: location)
            postEndpointEvent(secondUp, withShift: withShift, location: location)
        }
    }

    private func postEndpointEvent(
        _ event: CGEvent,
        withShift: Bool,
        location: CGPoint? = nil
    ) {
        let output = copyEvent(event)
        if let location {
            output.location = location
        }
        if withShift {
            output.flags.insert(.maskShift)
        }
        output.post(tap: .cghidEventTap)
    }

    private var frontmostApplicationIsFinder: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    private func snappedEndpointLocation(near point: CGPoint) -> CGPoint {
        let offsets = nearbySnapOffsets()

        for offset in offsets {
            let candidate = CGPoint(
                x: point.x + offset.x,
                y: point.y + offset.y
            )
            guard let element = accessibilityElement(at: candidate),
                  hasTextRange(at: candidate, in: element) else {
                continue
            }

            return candidate
        }

        return point
    }

    private func nearbySnapOffsets() -> [CGPoint] {
        var offsets = [CGPoint.zero]
        var radius = Self.endpointSnapStep
        while radius <= Self.endpointSnapRadius {
            offsets.append(contentsOf: [
                CGPoint(x: -radius, y: 0),
                CGPoint(x: radius, y: 0),
                CGPoint(x: 0, y: -radius),
                CGPoint(x: 0, y: radius),
                CGPoint(x: -radius, y: -radius),
                CGPoint(x: radius, y: -radius),
                CGPoint(x: -radius, y: radius),
                CGPoint(x: radius, y: radius)
            ])
            radius += Self.endpointSnapStep
        }
        return offsets
    }

    private func accessibilityElement(at point: CGPoint) -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            systemElement,
            Float(point.x),
            Float(point.y),
            &element
        )
        return error == .success ? element : nil
    }

    private func hasTextRange(at point: CGPoint, in element: AXUIElement) -> Bool {
        var pointValue = point
        guard let axPoint = AXValueCreate(.cgPoint, &pointValue) else {
            return false
        }

        var range: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXRangeForPositionParameterizedAttribute as CFString,
            axPoint,
            &range
        )
        return error == .success && range != nil
    }

    private func cancelEndpointWaiting() {
        endpointPendingWorkItem?.cancel()
        endpointPendingWorkItem = nil
        endpointPendingDown = nil
        endpointPendingUp = nil
        endpointPendingSecondDown = nil
        endpointPendingSecondUp = nil
        endpointPendingTapPoint = .zero
        endpointPendingTapAt = .distantPast
        endpointLastTapUpAt = .distantPast
        endpointDoubleTapCandidate = false
        isEndpointSelectionWaiting = false
    }

    private func resetEndpointSelectionState() {
        replayPendingEndpointClick(withShift: false)
        cancelEndpointWaiting()
        endpointLastTapUpAt = .distantPast
        endpointLastTapPoint = .zero
        endpointTapDownAt = .distantPast
        endpointTapDownPoint = .zero
        endpointTapMoved = false
        endpointDoubleTapCandidate = false
        endpointStartPoint = .zero
        isEndpointSelectionWaiting = false
    }

    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func handleScrollEvent(_ event: CGEvent, type: CGEventType) -> CGEvent? {
        guard type == .scrollWheel else { return event }

        // Once a gesture has crossed its trigger step, the action is
        // independent of the modifier's release timing. Swallow the tail of
        // that physical gesture while the window operation is being applied.
        if actionInProgress {
            return nil
        }

        let fixedDelta = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let pointDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let integerDelta = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        let deltaX: Double
        // Match the vertical path: pointDelta represents real trackpad travel.
        // fixedPtDelta is often much smaller and made a deliberate left swipe
        // fail to reach the shared horizontal threshold.
        if abs(pointDelta) > 0.01 {
            deltaX = pointDelta
        } else if abs(fixedDelta) > 0.01 {
            deltaX = fixedDelta
        } else {
            deltaX = integerDelta
        }
        let pointVerticalDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let fixedVerticalDelta = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let integerVerticalDelta = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let deltaY: Double
        // For trackpad vertical scrolling, pointDelta reflects the physical
        // finger travel. fixedPtDelta is a high precision scroll unit and is
        // often an order of magnitude smaller, which made a normal vertical
        // swipe fail to reach the snapshot threshold.
        if abs(pointVerticalDelta) > 0.01 {
            deltaY = pointVerticalDelta
        } else if abs(fixedVerticalDelta) > 0.01 {
            deltaY = fixedVerticalDelta
        } else {
            deltaY = integerVerticalDelta
        }
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let isEnded = scrollPhase == 4 || scrollPhase == 8
        let commandHeld = commandIsHeld(for: event)
        let hasHorizontalDelta = abs(deltaX) > 0.01
        let hasVerticalDelta = abs(deltaY) > 0.01

        let now = Date()
        if now < ignoreEventsUntil {
            if commandHeld || hasHorizontalDelta || hasVerticalDelta || momentumPhase != 0 {
                if isEnded && !gestureHasTriggered {
                    resetGestureState()
                } else if isEnded {
                    scheduleGestureEndReset()
                }
                return nil
            }
            return event
        }

        if commandGestureActive && !commandHeld {
            if hasHorizontalDelta || hasVerticalDelta || momentumPhase != 0 {
                if isEnded && !gestureHasTriggered {
                    resetGestureState()
                } else if isEnded {
                    scheduleGestureEndReset()
                }
                return nil
            }
            if isEnded && !gestureHasTriggered {
                resetGestureState()
                return nil
            } else if isEnded {
                scheduleGestureEndReset()
            }
            return event
        }

        guard commandHeld else { return event }

        // Command is an explicit modal gesture modifier: do not let the
        // foreground app see even the vertical/zero-horizontal samples in
        // this scroll sequence, otherwise it may start its own gesture state.
        guard hasHorizontalDelta || hasVerticalDelta else {
            if isEnded && !gestureHasTriggered {
                resetGestureState()
            } else if isEnded {
                scheduleGestureEndReset()
            }
            return nil
        }

        // Command + vertical and horizontal events are swallowed from the
        // beginning, so the foreground app cannot start its own gesture.
        if gestureHasTriggered {
            // One physical swipe is one command. Do not clear the consumed
            // state on a short timer and interpret its momentum as another
            // command. A new scroll-began event starts the next command even
            // when Command remains held.
            if scrollPhase == 1 {
                resetGestureState()
            } else {
                observeGestureEnd(scrollPhase: scrollPhase, momentumPhase: momentumPhase)
                return nil
            }
        }

        let startsNewGesture = !commandGestureActive ||
            now.timeIntervalSince(gestureStartedAt) > Self.gestureTimeout
        if startsNewGesture {
            horizontalDistance = 0
            verticalDistance = 0
            gestureHasTriggered = false
            commandGestureActive = true
            gestureStartedAt = now
        }

        horizontalDistance += CGFloat(deltaX)
        verticalDistance += CGFloat(deltaY)
        gestureStartedAt = now
        scheduleGestureReset(after: Self.gestureTimeout)

        let horizontalTriggered = abs(horizontalDistance) >= CGFloat(triggerThreshold)
        let verticalTriggered = abs(verticalDistance) >= Self.minimumSnapshotTriggerThreshold
        guard horizontalTriggered || verticalTriggered else {
            if isEnded {
                resetGestureState()
                return commandHeld ? nil : event
            }
            return nil
        }

        gestureHasTriggered = true
        // The pre-trigger timeout is no longer allowed to clear a committed
        // command. From this point, one physical swipe owns exactly one
        // action until Command is released.
        resetWorkItem?.cancel()
        resetWorkItem = nil
        let action: Action
        if verticalTriggered &&
            (!horizontalTriggered || abs(verticalDistance) > abs(horizontalDistance)) {
            // The trackpad's scroll-axis direction is opposite to the
            // physical finger direction on this machine: the negative axis
            // is the user's two-finger up gesture.
            action = verticalDistance < 0 ? .restoreSnapshot : .saveSnapshot
        } else {
            let fingerMovedRight = horizontalDistance > 0
            let effectiveRight = directionInverted ? !fingerMovedRight : fingerMovedRight
            action = effectiveRight ? .minimize : .cycle
        }

        ignoreEventsUntil = now.addingTimeInterval(Self.eventActionCooldown)
        actionInProgress = true
        // Return from the tap quickly. Window enumeration and AX activation can
        // take long enough to make macOS disable a synchronous event tap; that
        // would leak the tail of a left swipe back to the foreground app.
        DispatchQueue.main.async { [weak self] in
            self?.perform(action)
        }
        return nil
    }

    private func resetGestureState() {
        horizontalDistance = 0
        verticalDistance = 0
        gestureHasTriggered = false
        commandGestureActive = false
        resetWorkItem?.cancel()
        resetWorkItem = nil
        gestureEndWorkItem?.cancel()
        gestureEndWorkItem = nil
    }

    private func observeGestureEnd(scrollPhase: Int64, momentumPhase: Int64) {
        let momentumStarted = momentumPhase == 1 || momentumPhase == 2
        if momentumStarted {
            gestureEndWorkItem?.cancel()
            gestureEndWorkItem = nil
            return
        }

        let scrollEnded = scrollPhase == 4 || scrollPhase == 8
        let momentumEnded = momentumPhase == 4 || momentumPhase == 8
        if scrollEnded || momentumEnded {
            scheduleGestureEndReset()
        }
    }

    private func scheduleGestureEndReset() {
        gestureEndWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.resetGestureState()
        }
        gestureEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.gestureEndDebounce,
            execute: workItem
        )
    }

    private func scheduleGestureReset(after delay: TimeInterval) {
        resetWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.resetGestureState()
        }
        resetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private enum Action {
        case minimize
        case cycle
        case saveSnapshot
        case restoreSnapshot
    }

    private func perform(_ action: Action) {
        defer { actionInProgress = false }
        refreshPermission()

        guard accessibilityTrusted else {
            lastAction = "需要辅助功能权限，点击菜单里的“打开辅助功能设置”"
            return
        }

        let result: WindowActionResult
        switch action {
        case .minimize:
            result = WindowController.shared.minimizeCurrentWindow()
        case .cycle:
            result = WindowController.shared.activateNextWindow()
        case .saveSnapshot:
            result = WindowController.shared.captureCurrentWindowSnapshot()
        case .restoreSnapshot:
            result = WindowController.shared.restoreWindowSnapshot()
        }
        lastAction = result.message

        if case .success = result {
            switch action {
            case .saveSnapshot:
                snapshotFeedback.show(kind: .saved, detail: "窗口位置与层级已记录")
            case .restoreSnapshot:
                snapshotFeedback.show(kind: .restored, detail: "窗口位置与层级已恢复")
            case .minimize, .cycle:
                break
            }
        } else {
            switch action {
            case .saveSnapshot:
                snapshotFeedback.show(kind: .saveFailed, detail: result.message)
            case .restoreSnapshot:
                snapshotFeedback.show(kind: .restoreFailed, detail: result.message)
            case .minimize, .cycle:
                break
            }
        }
    }
}
