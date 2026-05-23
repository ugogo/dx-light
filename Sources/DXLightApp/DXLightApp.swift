import AppKit
import Combine
import DXLightCore
import SwiftUI

@main
struct DXLightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let controller = LightController()
    private let loginItemController = LoginItemController()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()
    private var powerEventTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 340)
        popover.behavior = .transient
        popover.delegate = self
        self.popover = popover

        controller.start()
        registerPowerNotifications()
        updateStatusIcon()

        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        powerEventTask?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        controller.stop()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        if let event = NSApp.currentEvent, event.modifierFlags.contains(.option) {
            Task {
                await controller.togglePower()
                updateStatusIcon()
            }
            return
        }

        guard let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        guard let popover else { return }
        loginItemController.refreshStatus()

        popover.contentViewController = NSHostingController(
            rootView: MenuPopoverView(
                controller: controller,
                loginItemController: loginItemController
            )
        )

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func popoverDidShow(_ notification: Notification) {
        popover?.contentViewController?.view.window?.makeKey()
    }

    private func registerPowerNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(workspaceWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func workspaceWillSleep(_ notification: Notification) {
        powerEventTask?.cancel()
        powerEventTask = Task { [controller] in
            await controller.prepareForSystemSleep()
            updateStatusIcon()
        }
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        powerEventTask?.cancel()
        powerEventTask = Task { [controller] in
            await controller.restoreAfterSystemWake()
            updateStatusIcon()
        }
    }

    private func updateStatusIcon() {
        let symbol = controller.menuBarSymbol
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "DX Light"
        )
        statusItem?.button?.image?.isTemplate = true
    }
}

extension LightController {
    var menuBarSymbol: String {
        switch status {
        case .connected:
            return isOn ? "lightbulb.fill" : "lightbulb"
        case .searching:
            return "lightbulb.circle"
        case .error:
            return "lightbulb.slash"
        }
    }
}
