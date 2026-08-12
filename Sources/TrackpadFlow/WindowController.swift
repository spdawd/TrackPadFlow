import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum WindowActionResult {
    case success(String)
    case unavailable(String)

    var message: String {
        switch self {
        case .success(let message), .unavailable(let message):
            return message
        }
    }
}

final class WindowController: @unchecked Sendable {
    static let shared = WindowController()

    private let ownBundleIdentifier = Bundle.main.bundleIdentifier
    // 右滑压栈，左滑只从栈顶恢复；不再扫描和排序全部后台窗口。
    private var minimizedStack: [WindowTarget] = []
    private var windowSnapshot: [WindowSnapshotEntry] = []

    private init() {}

    func minimizeCurrentWindow() -> WindowActionResult {
        guard let app = frontmostRegularApplication() else {
            return .unavailable("没有找到可以最小化的前台窗口")
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = focusedWindow(in: axApp) else {
            return .unavailable("无法读取当前窗口；请确认已授予辅助功能权限")
        }

        let target = makeTarget(for: app, window: window)
        let error = AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        )
        guard error == .success else {
            return .unavailable("当前窗口不支持最小化（\(errorDescription(error))）")
        }

        minimizedStack.append(target)

        let appName = app.localizedName ?? "当前窗口"
        guard let nextTarget = topmostTarget(excluding: app.processIdentifier) else {
            return .success("已最小化 \(appName)，恢复栈已记录")
        }

        switch activate(nextTarget) {
        case .success:
            let targetName = nextTarget.title.isEmpty
                ? (nextTarget.application.localizedName ?? "下一个窗口")
                : nextTarget.title
            return .success("已最小化 \(appName)，焦点已转移到 \(targetName)")
        case .failure:
            return .success("已最小化 \(appName)，恢复栈已记录，但无法自动选中上层窗口")
        }
    }

    // 从恢复栈中唤醒下一个窗口。
    func activateNextWindow() -> WindowActionResult {
        while let target = minimizedStack.popLast() {
            guard !target.application.isTerminated else { continue }

            switch activate(target) {
            case .success:
                let appName = target.application.localizedName ?? "窗口"
                let title = target.title.isEmpty ? appName : target.title
                return .success("已从恢复栈唤醒 \(title)")
            case .failure(let error):
                // 目标可能暂时无响应，保留在栈顶，下一次左滑可以重试。
                minimizedStack.append(target)
                return .unavailable("恢复 \(target.title.isEmpty ? "窗口" : target.title) 失败（\(errorDescription(error))）")
            }
        }

        return .unavailable("恢复栈为空；请先用右滑最小化窗口")
    }

    func captureCurrentWindowSnapshot() -> WindowActionResult {
        let visibleWindows = windowListInfo()
        // A CGWindowList contains every on-screen layer-0 window, including
        // windows completely covered by a nearer window. Keep only windows
        // that contribute visible pixels to the current composition; this
        // makes restoring a scene both calmer and more faithful to what the
        // user actually saw.
        let visualWindows = visuallyVisibleWindows(from: visibleWindows)
        var captured: [WindowSnapshotEntry] = []

        for info in visualWindows {
            guard let app = regularApplication(for: info.processIdentifier),
                  app.bundleIdentifier != ownBundleIdentifier,
                  !app.isHidden,
                  let window = matchingWindow(for: info, in: app),
                  let frame = frame(of: window) else {
                continue
            }

            captured.append(
                WindowSnapshotEntry(
                    processIdentifier: info.processIdentifier,
                    application: app,
                    title: copyStringAttribute(kAXTitleAttribute, from: window) ?? info.title,
                    frame: frame,
                    zOrder: info.zOrder
                )
            )
        }

        guard !captured.isEmpty else {
            return .unavailable("当前没有可保存的普通窗口")
        }

        windowSnapshot = captured
        return .success("已保持当前工作场景")
    }

    func restoreWindowSnapshot() -> WindowActionResult {
        guard !windowSnapshot.isEmpty else {
            return .unavailable("还没有工作场景快照；请先 Command + 两指下滑保持")
        }

        var restored: [(entry: WindowSnapshotEntry, element: AXUIElement)] = []

        for entry in windowSnapshot {
            guard !entry.application.isTerminated,
                  let window = resolveWindow(for: entry) else {
                continue
            }

            let minimized = (copyAttributeValue(
                kAXMinimizedAttribute,
                from: window
            ) as? NSNumber)?.boolValue ?? false
            if minimized {
                _ = AXUIElementSetAttributeValue(
                    window,
                    kAXMinimizedAttribute as CFString,
                    kCFBooleanFalse
                )
            }

            if let currentFrame = frame(of: window),
               frameDistance(currentFrame, entry.frame) > 1 {
                _ = setFrame(entry.frame, for: window)
            }
            restored.append((entry, window))
        }

        guard !restored.isEmpty else {
            return .unavailable("快照中的窗口已关闭或无法访问")
        }

        // Cross-application AXRaise alone is not sufficient: an inactive app
        // may keep its window behind the current app. Activate each saved
        // window in back-to-front order so one restore command really brings
        // the complete visual workspace back.
        let backToFront = restored.sorted { $0.entry.zOrder > $1.entry.zOrder }
        for item in backToFront {
            let target = makeTarget(for: item.entry.application, window: item.element)
            _ = activate(target)
        }

        return .success("已恢复工作场景")
    }

    private func topmostTarget(excluding excludedProcessIdentifier: pid_t) -> WindowTarget? {
        var seenApplications = Set<pid_t>()
        for info in windowListInfo() {
            guard info.processIdentifier != excludedProcessIdentifier,
                  seenApplications.insert(info.processIdentifier).inserted,
                  let app = NSRunningApplication(processIdentifier: info.processIdentifier),
                  app.activationPolicy == .regular,
                  !app.isHidden,
                  !app.isTerminated,
                  app.bundleIdentifier != ownBundleIdentifier,
                  let window = focusedWindow(in: AXUIElementCreateApplication(info.processIdentifier)) else {
                continue
            }

            return makeTarget(for: app, window: window)
        }
        return nil
    }

    private func activate(_ target: WindowTarget) -> ActivationResult {
        let isMinimized = (copyAttributeValue(
            kAXMinimizedAttribute,
            from: target.element
        ) as? NSNumber)?.boolValue ?? target.isMinimized

        if isMinimized {
            let restoreError = AXUIElementSetAttributeValue(
                target.element,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
            guard restoreError == .success else {
                return .failure(restoreError)
            }
        }

        guard target.application.activate(options: []) else {
            return .failure(.cannotComplete)
        }

        let mainError = AXUIElementSetAttributeValue(
            target.element,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        let focusedError = AXUIElementSetAttributeValue(
            target.element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        let raiseError = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)

        if raiseError == .success ||
            mainError == .success ||
            focusedError == .success {
            return .success
        }
        return .failure(raiseError)
    }

    private func frontmostRegularApplication() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.activationPolicy == .regular,
              app.bundleIdentifier != ownBundleIdentifier else {
            return nil
        }
        return app
    }

    private func regularApplication(for processIdentifier: pid_t) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: processIdentifier),
              app.activationPolicy == .regular,
              !app.isTerminated else {
            return nil
        }
        return app
    }

    private func matchingWindow(
        for info: CGWindowInfo,
        in app: NSRunningApplication
    ) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = copyWindows(from: axApp), !windows.isEmpty else { return nil }

        let titleMatches = windows.filter { window in
            let title = copyStringAttribute(kAXTitleAttribute, from: window) ?? ""
            return info.title.isEmpty || title.isEmpty || title == info.title
        }
        let candidates = titleMatches.isEmpty ? windows : titleMatches

        return candidates
            .compactMap { window -> (window: AXUIElement, score: CGFloat)? in
                guard let windowFrame = frame(of: window) else { return nil }
                return (window, frameDistance(windowFrame, info.frame))
            }
            .min(by: { $0.score < $1.score })?.window
    }

    private func resolveWindow(for entry: WindowSnapshotEntry) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(entry.processIdentifier)
        guard let windows = copyWindows(from: axApp), !windows.isEmpty else { return nil }

        let titleMatches = windows.filter { window in
            let title = copyStringAttribute(kAXTitleAttribute, from: window) ?? ""
            return entry.title.isEmpty || title.isEmpty || title == entry.title
        }
        let candidates = titleMatches.isEmpty ? windows : titleMatches

        return candidates
            .compactMap { window -> (window: AXUIElement, score: CGFloat)? in
                guard let windowFrame = frame(of: window) else { return nil }
                return (window, frameDistance(windowFrame, entry.frame))
            }
            .min(by: { $0.score < $1.score })?.window
    }


    private func frame(of window: AXUIElement) -> CGRect? {
        guard let positionAttribute = copyAttributeValue(kAXPositionAttribute, from: window),
              let sizeAttribute = copyAttributeValue(kAXSizeAttribute, from: window) else {
            return nil
        }
        let positionValue = positionAttribute as! AXValue
        let sizeValue = sizeAttribute as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func setFrame(_ frame: CGRect, for window: AXUIElement) -> Bool {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }

        let positionError = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            positionValue
        )
        let sizeError = AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        return positionError == .success || sizeError == .success
    }

    private func frameDistance(_ first: CGRect, _ second: CGRect) -> CGFloat {
        abs(first.midX - second.midX) +
            abs(first.midY - second.midY) +
            abs(first.width - second.width) +
            abs(first.height - second.height)
    }

    private func focusedWindow(in axApp: AXUIElement) -> AXUIElement? {
        if let focused = copyElementAttribute(kAXFocusedWindowAttribute, from: axApp) {
            return focused
        }
        if let main = copyElementAttribute(kAXMainWindowAttribute, from: axApp) {
            return main
        }
        guard let windows = copyWindows(from: axApp) else { return nil }
        return windows.first
    }

    private func makeTarget(for app: NSRunningApplication, window: AXUIElement) -> WindowTarget {
        let title = copyStringAttribute(kAXTitleAttribute, from: window) ?? ""
        let isMinimized = (copyAttributeValue(
            kAXMinimizedAttribute,
            from: window
        ) as? NSNumber)?.boolValue ?? false
        return WindowTarget(
            processIdentifier: app.processIdentifier,
            application: app,
            title: title,
            element: window,
            isMinimized: isMinimized
        )
    }

    private func windowListInfo() -> [CGWindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return list.enumerated().compactMap { index, info in
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0 else {
                return nil
            }

            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0 else { return nil }
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else {
                return nil
            }

            return CGWindowInfo(
                windowID: CGWindowID(windowID),
                processIdentifier: pid,
                title: info[kCGWindowName as String] as? String ?? "",
                frame: frame,
                zOrder: index
            )
        }
    }

    private func visuallyVisibleWindows(from windows: [CGWindowInfo]) -> [CGWindowInfo] {
        var coveredFrames: [CGRect] = []
        var result: [CGWindowInfo] = []

        // CGWindowList is ordered from front to back. Every valid window is
        // an occluder for the windows below it, even if it is TrackpadFlow's
        // own panel and therefore will not be saved.
        for window in windows {
            let frame = window.frame.standardized
            guard !frame.isEmpty else { continue }

            let visibleArea = uncoveredArea(of: frame, coveredBy: coveredFrames)
            let totalArea = frame.width * frame.height
            // A thin visible strip is usually a background window rather
            // than part of the user's working composition. Requiring a
            // A meaningful visible ratio keeps the snapshot focused on
            // working windows while still retaining a window that is partly
            // overlapped but clearly part of the user's visual workspace.
            let meaningfulArea = max(1_500, totalArea * 0.20)
            if visibleArea >= meaningfulArea {
                result.append(window)
            }
            coveredFrames.append(frame)
        }

        return result
    }

    private func uncoveredArea(of frame: CGRect, coveredBy coveredFrames: [CGRect]) -> CGFloat {
        var pieces = [frame]

        for coveredFrame in coveredFrames {
            pieces = pieces.flatMap { subtract($0, coveredFrame) }
            if pieces.isEmpty { break }
        }

        return pieces.reduce(0) { $0 + ($1.width * $1.height) }
    }

    private func subtract(_ frame: CGRect, _ coveredFrame: CGRect) -> [CGRect] {
        let intersection = frame.intersection(coveredFrame)
        guard !intersection.isNull, !intersection.isEmpty else { return [frame] }

        var pieces: [CGRect] = []
        if intersection.minY > frame.minY {
            pieces.append(
                CGRect(
                    x: frame.minX,
                    y: frame.minY,
                    width: frame.width,
                    height: intersection.minY - frame.minY
                )
            )
        }
        if intersection.maxY < frame.maxY {
            pieces.append(
                CGRect(
                    x: frame.minX,
                    y: intersection.maxY,
                    width: frame.width,
                    height: frame.maxY - intersection.maxY
                )
            )
        }
        if intersection.minX > frame.minX {
            pieces.append(
                CGRect(
                    x: frame.minX,
                    y: intersection.minY,
                    width: intersection.minX - frame.minX,
                    height: intersection.height
                )
            )
        }
        if intersection.maxX < frame.maxX {
            pieces.append(
                CGRect(
                    x: intersection.maxX,
                    y: intersection.minY,
                    width: frame.maxX - intersection.maxX,
                    height: intersection.height
                )
            )
        }
        return pieces.filter { !$0.isEmpty }
    }

    private func copyWindows(from app: AXUIElement) -> [AXUIElement]? {
        guard let value = copyAttributeValue(kAXWindowsAttribute, from: app) else { return nil }
        return value as? [AXUIElement]
    }

    private func copyElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private func copyAttributeValue(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        copyAttributeValue(attribute, from: element) as? String
    }

    private func errorDescription(_ error: AXError) -> String {
        switch error {
        case .success: return "成功"
        case .failure: return "失败"
        case .illegalArgument: return "参数不支持"
        case .invalidUIElement: return "窗口已失效"
        case .invalidUIElementObserver: return "观察器已失效"
        case .cannotComplete: return "应用暂时无响应"
        case .attributeUnsupported: return "属性不支持"
        case .actionUnsupported: return "动作不支持"
        case .notificationUnsupported: return "通知不支持"
        case .notImplemented: return "未实现"
        case .notificationAlreadyRegistered: return "通知已注册"
        case .notificationNotRegistered: return "通知未注册"
        case .apiDisabled: return "辅助功能 API 未启用"
        case .noValue: return "没有窗口值"
        case .parameterizedAttributeUnsupported: return "属性不支持"
        case .notEnoughPrecision: return "精度不足"
        @unknown default: return "未知错误"
        }
    }
}

private enum ActivationResult {
    case success
    case failure(AXError)
}

private struct CGWindowInfo {
    let windowID: CGWindowID
    let processIdentifier: pid_t
    let title: String
    let frame: CGRect
    let zOrder: Int
}

private struct WindowTarget {
    let processIdentifier: pid_t
    let application: NSRunningApplication
    let title: String
    let element: AXUIElement
    let isMinimized: Bool
}

private struct WindowSnapshotEntry {
    let processIdentifier: pid_t
    let application: NSRunningApplication
    let title: String
    let frame: CGRect
    let zOrder: Int
}
