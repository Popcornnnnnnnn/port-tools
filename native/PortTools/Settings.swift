import AppKit
import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    @StateObject private var store = InventoryStore()
    @AppStorage("appearanceMode") private var appearance = AppearanceMode.system.rawValue
    @AppStorage("language") private var language = "system"
    @AppStorage("SUEnableAutomaticChecks") private var automaticChecks = false
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?

    private var ignoredServices: [ServiceRecord] {
        (store.document?.services ?? []).filter(\.preferences.ignored)
    }

    var body: some View {
        Form {
            Picker("Language", selection: $language) {
                Text("System").tag("system")
                Text("English").tag("en")
                Text("简体中文").tag("zh-Hans")
            }
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
            }
            Toggle("Open at Login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        errorMessage = error.localizedDescription
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Toggle("Automatically check for updates", isOn: $automaticChecks)
            Button("Check for Updates…") { UpdaterBridge.shared.checkForUpdates() }

            Section("Ignored") {
                if ignoredServices.isEmpty {
                    Text("No ignored services").foregroundStyle(.secondary)
                } else {
                    ForEach(ignoredServices) { service in
                        HStack {
                            Text(serviceName(service))
                            Spacer()
                            Text(":\(service.listener.port)").font(.system(.body, design: .monospaced))
                            Button("Restore") {
                                store.updatePreferences(service, patch: ["ignored": false]) { result in
                                    if case .failure(let error) = result { errorMessage = error.localizedDescription }
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button("Reset Local Data and Quit…", role: .destructive) {
                    let alert = NSAlert()
                    alert.messageText = portToolsString("Reset all Port Tools data and quit?")
                    alert.informativeText = portToolsString("Routes, names, pins, ignored services, history and preferences will be removed from this Mac.")
                    alert.addButton(withTitle: portToolsString("Reset and Quit"))
                    alert.addButton(withTitle: portToolsString("Cancel"))
                    if alert.runModal() == .alertFirstButtonReturn {
                        AppMaintenance.resetLocalDataAndQuit()
                    }
                }
            }

            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 520)
        .task { store.refresh() }
        .environment(\.locale, portToolsLocale(language))
    }
}
