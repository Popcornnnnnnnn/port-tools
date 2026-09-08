import AppKit
import Foundation
import ServiceManagement
import SwiftUI

enum AppMaintenance {
    static let migrationMarker = "didMigrateDevPortToolsTrial"

    static func migrateTrialPreferences() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationMarker) else { return }
        if let old = defaults.persistentDomain(forName: "dev.port-tools.trial") {
            for key in ["projectDisplayNames", "serviceDisplayNames", "appearanceMode", "language"]
                where defaults.object(forKey: key) == nil && old[key] != nil {
                defaults.set(old[key], forKey: key)
            }
        }
        defaults.set(true, forKey: migrationMarker)
    }

    @MainActor
    static func resetLocalDataAndQuit() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
        CoreRuntime.shared.stop()
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        for domain in ["xyz.popcornnn.PortTools", "dev.port-tools.trial"] {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        let targets = [
            home.appendingPathComponent("Library/Application Support/Port Tools", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/xyz.popcornnn.PortTools", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/dev.port-tools.trial", isDirectory: true),
            home.appendingPathComponent("Library/Logs/Port Tools", isDirectory: true),
            home.appendingPathComponent("Library/Logs/xyz.popcornnn.PortTools", isDirectory: true),
            home.appendingPathComponent("Library/Logs/dev.port-tools.trial", isDirectory: true),
            home.appendingPathComponent("Library/Caches/xyz.popcornnn.PortTools", isDirectory: true),
            home.appendingPathComponent("Library/Caches/dev.port-tools.trial", isDirectory: true),
            home.appendingPathComponent("Library/HTTPStorages/xyz.popcornnn.PortTools", isDirectory: true),
            home.appendingPathComponent("Library/HTTPStorages/dev.port-tools.trial", isDirectory: true),
            home.appendingPathComponent("Library/Preferences/xyz.popcornnn.PortTools.plist"),
            home.appendingPathComponent("Library/Preferences/dev.port-tools.trial.plist"),
        ]
        for target in targets { try? manager.removeItem(at: target) }
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
final class PortToolsAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var previewWindow: NSWindow?
    private var previewStore: InventoryStore?
    private var statusItem: NSStatusItem?
    private var statusPopover: NSPopover?
    private var statusStore: InventoryStore?
    private var openScanTimer: Timer?
    private var backgroundScanTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMaintenance.migrateTrialPreferences()
        _ = UpdaterBridge.shared
        do {
            try CoreRuntime.shared.start()
        } catch {
            NSLog("Port Tools startup failed: %@", error.localizedDescription)
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--preview-window") {
            showPreviewWindow()
        } else {
            installStatusItem()
        }
        offerAutomaticUpdatesOnSecondLaunch()
    }

    private func offerAutomaticUpdatesOnSecondLaunch() {
        if ProcessInfo.processInfo.environment["PORT_TOOLS_DISABLE_PROMPTS"] == "1" { return }
        let defaults = UserDefaults.standard
        let launches = defaults.integer(forKey: "launchCount")
        defaults.set(launches + 1, forKey: "launchCount")
        guard launches == 1, !defaults.bool(forKey: "didAskAutomaticUpdates") else { return }
        defaults.set(true, forKey: "didAskAutomaticUpdates")
        let alert = NSAlert()
        alert.messageText = portToolsString("Automatically check for Port Tools updates?")
        alert.informativeText = portToolsString("Port Tools can periodically check updates.popcornnn.xyz. You can change this later in Settings.")
        alert.addButton(withTitle: portToolsString("Check Automatically"))
        alert.addButton(withTitle: portToolsString("Not Now"))
        if alert.runModal() == .alertFirstButtonReturn {
            defaults.set(true, forKey: "SUEnableAutomaticChecks")
        }
    }

    private func showPreviewWindow() {
        let store = InventoryStore()
        store.refresh()
        let host = NSHostingView(rootView: LocalizedInventoryView(store: store))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: inventoryPanelWidth, height: inventoryPanelHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Port Tools Preview"
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewStore = store
        previewWindow = window
    }

    private func installStatusItem() {
        let store = InventoryStore()
        store.refresh()

        let item = NSStatusBar.system.statusItem(withLength: 24)
        if let button = item.button {
            let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let image = NSImage(systemSymbolName: "network", accessibilityDescription: "Port Tools")?
                .withSymbolConfiguration(configuration)
            image?.isTemplate = true
            image?.size = NSSize(width: 16, height: 16)
            button.image = image
            button.imageScaling = .scaleNone
            button.imagePosition = .imageOnly
            button.toolTip = "Port Tools"
            button.target = self
            button.action = #selector(toggleStatusPopover(_:))
        }

        statusStore = store
        statusItem = item
        backgroundScanTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.statusStore?.refresh(silent: true) }
        }
    }

    private func makeStatusPopover(store: InventoryStore) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: inventoryPanelWidth, height: inventoryPanelHeight)
        popover.contentViewController = NSHostingController(rootView: LocalizedInventoryView(store: store))
        return popover
    }

    @objc private func toggleStatusPopover(_ sender: Any?) {
        guard let button = statusItem?.button, let statusStore else { return }
        if let statusPopover, statusPopover.isShown {
            statusPopover.performClose(sender)
        } else {
            let statusPopover = makeStatusPopover(store: statusStore)
            self.statusPopover = statusPopover
            statusStore.refresh(silent: true)
            statusPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            openScanTimer?.invalidate()
            openScanTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.statusStore?.refresh(silent: true) }
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        openScanTimer?.invalidate()
        openScanTimer = nil
        statusPopover = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        openScanTimer?.invalidate()
        backgroundScanTimer?.invalidate()
        CoreRuntime.shared.stop()
    }
}

@main
struct PortToolsApp: App {
    @NSApplicationDelegateAdaptor(PortToolsAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}
