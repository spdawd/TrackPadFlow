import AppKit
import SwiftUI

@main
struct TrackpadFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: GestureController!
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = GestureController()
        configureStatusItem()
        configurePopover()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "hand.draw.fill",
                accessibilityDescription: "TrackpadFlow"
            )
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "TrackpadFlow"
        }
    }

    private func configurePopover() {
        let panel = NSPopover()
        panel.behavior = .transient
        panel.animates = true
        panel.contentSize = NSSize(width: 390, height: 760)
        panel.contentViewController = NSHostingController(
            rootView: ControlPanelView()
                .environmentObject(controller)
        )
        popover = panel
    }

    @objc private func togglePopover() {
        guard let panel = popover,
              let button = statusItem?.button else {
            return
        }

        if panel.isShown {
            panel.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            panel.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
    }
}
