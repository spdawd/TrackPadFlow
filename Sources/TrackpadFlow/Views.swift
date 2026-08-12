import AppKit
import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject private var controller: GestureController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            permissionCard
            gestureCard
            settingsCard
            footer
        }
        .padding(16)
        .frame(width: 390)
        .onAppear {
            controller.refreshPermission()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TrackpadFlow")
                    .font(.headline)
                Text("用两指横向滑动控制窗口")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            logoImage
        }
    }

    private var logoImage: some View {
        if let image = ControlPanelAssets.logo {
            return AnyView(
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            )
        }

        return AnyView(
            Image(systemName: "hand.draw")
                .font(.title2)
                .foregroundStyle(.blue)
        )
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(
                    controller.isMonitoring ? "权限与手势拦截" : "权限",
                    systemImage: controller.accessibilityTrusted && controller.isMonitoring
                        ? "checkmark.shield.fill"
                        : "exclamationmark.shield.fill"
                )
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(permissionStatus)
                    .font(.caption)
                    .foregroundStyle(controller.accessibilityTrusted && controller.isMonitoring ? .green : .orange)
            }

            Text(permissionDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !controller.accessibilityTrusted {
                Button {
                    controller.requestAccessibilityPermission()
                } label: {
                    Label("一键申请并打开系统设置", systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if controller.permissionRequestSent {
                    Label("请求已发送，请在列表中开启 TrackpadFlow", systemImage: "arrow.up.right.square")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Text("macOS 会要求你亲自确认开关；App 无法静默替你授权。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if !controller.isMonitoring {
                Button("打开输入监控设置") {
                    controller.openInputMonitoringSettings()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .cardStyle()
    }

    private var gestureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("手势", systemImage: "hand.draw.fill")
                .font(.subheadline.weight(.semibold))

            gestureRow(
                symbol: "arrow.right",
                title: "Command + 两指右滑",
                detail: controller.directionInverted ? "恢复栈顶窗口" : "最小化当前窗口"
            )
            gestureRow(
                symbol: "arrow.left",
                title: "Command + 两指左滑",
                detail: controller.directionInverted ? "最小化当前窗口" : "恢复栈顶窗口"
            )
            gestureRow(
                symbol: "arrow.down",
                title: "Command + 两指下滑",
                detail: "保持当前工作场景"
            )
            gestureRow(
                symbol: "arrow.up",
                title: "Command + 两指上滑",
                detail: "恢复工作场景"
            )

            Text("必须按住 Command；横向手势控制窗口，纵向手势保持或恢复当前可见窗口的位置与层级。按住期间会拦截整段滚动，避免当前应用启动自己的手势。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle("反转横向方向", isOn: $controller.directionInverted)
                .toggleStyle(.switch)
                .font(.callout)

            Text(controller.directionDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle("显示鼠标点击反馈", isOn: $controller.clickFeedbackEnabled)
                .toggleStyle(.switch)
                .font(.callout)

            Text("检测全局鼠标左键点击，在点击位置显示短暂青蓝波纹；不会拦截点击或抢走焦点。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("双击端点框选", isOn: $controller.endpointSelectionEnabled)
                .toggleStyle(.switch)
                .font(.callout)

            Text("起点双击后进入等待；双指滚动到另一端，再次双击，以 Shift-click 扩展选区。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("二次点击窗口")
                    Spacer()
                    Text("\(controller.endpointDoubleTapWindow, specifier: "%.2f") 秒")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                Slider(
                    value: $controller.endpointDoubleTapWindow,
                    in: GestureController.minimumEndpointDoubleTapWindow...GestureController.maximumEndpointDoubleTapWindow,
                    step: 0.05
                )

                HStack {
                    Text("更快确认")
                    Spacer()
                    Text("更宽松")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text("终点第一次点击会短暂等待第二击；普通单点超时后原样放行。Finder 和起点附近的连续双击始终由当前 App 原生处理。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("触发步长（左右共用）")
                    Spacer()
                    Text("\(Int(controller.triggerThreshold)) pt")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                Slider(
                    value: $controller.triggerThreshold,
                    in: 40...180,
                    step: 4
                )

                HStack {
                    Text("更灵敏")
                    Spacer()
                    Text("更稳")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text("数值越大，需要滑得更远才会触发；想更灵敏可调到 72–100 pt。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .cardStyle()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(controller.lastAction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Circle()
                    .fill(controller.isEndpointSelectionWaiting ? .blue : (controller.isMonitoring ? .green : .orange))
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    private func gestureRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.blue)
            Text(title)
                .font(.callout)
            Spacer()
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionStatus: String {
        if !controller.accessibilityTrusted {
            return "未开启辅助功能"
        }
        return controller.isMonitoring ? "已开启" : "需要输入监控"
    }

    private var permissionDescription: String {
        if !controller.accessibilityTrusted {
            return "窗口最小化和切换需要 macOS 的辅助功能权限。"
        }
        if !controller.isMonitoring {
            return "屏蔽应用自身横向滚动需要 Event Tap，请在输入监控中允许 TrackpadFlow。"
        }
        return "窗口控制和 Command + 横向手势拦截已准备好。"
    }

    private var statusText: String {
        if controller.isEndpointSelectionWaiting {
            return "等待第二个端点双击"
        }
        return controller.isMonitoring ? "正在拦截 Command + 连续横向滚动" : "需要输入监控权限"
    }
}

private enum ControlPanelAssets {
    static let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "TrackpadFlow-logo", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(11)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
    }
}
