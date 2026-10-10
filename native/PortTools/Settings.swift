import AppKit
import ServiceManagement
import SwiftUI

@MainActor
func applyPortToolsAppearance(_ rawValue: String) {
    switch AppearanceMode(rawValue: rawValue) ?? .dark {
    case .system:
        NSApp.appearance = nil
    case .light:
        NSApp.appearance = NSAppearance(named: .aqua)
    case .dark:
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

struct PreferencesView: View {
    @StateObject private var store = InventoryStore()
    @ObservedObject private var portless = PortlessServiceController.shared
    @AppStorage("appearanceMode") private var appearance = AppearanceMode.dark.rawValue
    @AppStorage("language") private var language = "system"
    @AppStorage("SUEnableAutomaticChecks") private var automaticChecks = false
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?
    @State private var scrollIndicator = ScrollIndicatorModel()

    private var ignoredServices: [ServiceRecord] {
        (store.document?.services ?? []).filter(\.preferences.ignored)
    }

    private var preferredColorScheme: ColorScheme? {
        switch AppearanceMode(rawValue: appearance) ?? .dark {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    generalSection
                    localServicesSection
                    ignoredSection
                    applicationSection

                    if let errorMessage {
                        statusBanner(errorMessage, color: .red, systemImage: "exclamationmark.triangle.fill")
                    } else if let portlessError = portless.lastError {
                        statusBanner(portlessError, color: .orange, systemImage: "exclamationmark.triangle.fill")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(TransientScrollViewConfigurator(model: scrollIndicator))
            }
            .scrollIndicators(.hidden)
            .contentMargins(.trailing, 0, for: .scrollContent)
            .overlay(alignment: .topTrailing) {
                TransientScrollIndicator(model: scrollIndicator)
            }
        }
        .frame(width: 540, height: 600)
        .preferredColorScheme(preferredColorScheme)
        .task {
            applyPortToolsAppearance(appearance)
            store.refresh()
            portless.refreshRouting()
        }
        .onChange(of: appearance) { _, value in
            applyPortToolsAppearance(value)
        }
        .environment(\.locale, portToolsLocale(language))
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.gradient)
                Image(systemName: "network")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            .shadow(color: Color.accentColor.opacity(0.2), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Port Tools")
                    .font(.system(size: 19, weight: .bold))
                Text("Manage how Port Tools looks and works on this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generalSection: some View {
        SettingsSection(title: "General", systemImage: "slider.horizontal.3") {
            SettingsRow(
                systemImage: "globe",
                title: "Language",
                detail: "Choose the language used throughout Port Tools."
            ) {
                Picker("Language", selection: $language) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                    Text("简体中文").tag("zh-Hans")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 132)
            }

            SettingsDivider()

            SettingsRow(
                systemImage: "circle.lefthalf.filled",
                title: "Appearance",
                detail: "Use the system appearance or choose a fixed theme."
            ) {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 196)
            }

            SettingsDivider()

            SettingsRow(
                systemImage: "power",
                title: "Open at Login",
                detail: "Keep local services visible after you sign in."
            ) {
                Toggle("Open at Login", isOn: $openAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: openAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            errorMessage = error.localizedDescription
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
    }

    private var localServicesSection: some View {
        SettingsSection(title: "Local Services", systemImage: "point.3.connected.trianglepath.dotted") {
            SettingsRow(
                systemImage: "link",
                title: "Port-free local addresses",
                detail: portless.runtimeStatus.message
            ) {
                Toggle("Port-free local addresses", isOn: Binding(
                    get: { portless.isRegistered },
                    set: { enabled in
                        if enabled { portless.enable() }
                        else { portless.disable() }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            SettingsDivider()

            SettingsRow(
                systemImage: "arrow.triangle.2.circlepath",
                title: "Automatic updates",
                detail: "Periodically check for new versions of Port Tools."
            ) {
                HStack(spacing: 10) {
                    Button("Check Now") { UpdaterBridge.shared.checkForUpdates() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Toggle("Automatically check for updates", isOn: $automaticChecks)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: automaticChecks) { _, enabled in
                            if enabled { _ = UpdaterBridge.shared }
                        }
                }
            }
        }
    }

    private var ignoredSection: some View {
        SettingsSection(title: "Ignored", systemImage: "eye.slash") {
            if ignoredServices.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No ignored services")
                            .font(.system(size: 13, weight: .medium))
                        Text("Services you ignore will appear here so you can restore them later.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
            } else {
                ForEach(Array(ignoredServices.enumerated()), id: \.element.id) { index, service in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(
                        systemImage: "eye.slash",
                        title: serviceName(service),
                        detail: "Port :\(service.listener.port)"
                    ) {
                        Button("Restore") {
                            store.updatePreferences(service, patch: ["ignored": false]) { result in
                                if case .failure(let error) = result {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var applicationSection: some View {
        SettingsSection(title: "Application", systemImage: "app.badge") {
            HStack(spacing: 10) {
                Button("Quit Port Tools") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)

                Spacer()

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
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
        }
    }

    private func statusBanner(_ message: String, color: Color, systemImage: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
            Text(message)
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 13)
        .frame(minHeight: 38)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 15)
                Text(portToolsString(title))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 5)

            VStack(spacing: 0) {
                content
            }
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 8, y: 2)
        }
    }
}

private struct SettingsRow<Accessory: View>: View {
    let systemImage: String
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(portToolsString(title))
                    .font(.system(size: 13, weight: .medium))
                Text(portToolsString(detail))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 52)
    }
}
