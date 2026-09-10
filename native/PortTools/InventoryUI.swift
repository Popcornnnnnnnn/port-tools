import AppKit
import Combine
import Foundation
import SwiftUI

private let webClassifications = Set(["confirmed-web", "suspected-web"])

func commandApplicationName(_ service: ServiceRecord) -> String? {
    guard let command = service.process.command else { return nil }
    let extensions = Set(["js", "mjs", "cjs", "ts", "py", "rb"])
    for part in command.split(whereSeparator: { $0.isWhitespace }).reversed() {
        let path = String(part).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let url = URL(fileURLWithPath: path)
        if extensions.contains(url.pathExtension.lowercased()) {
            return url.deletingPathExtension().lastPathComponent
        }
    }
    return nil
}

func serviceName(_ service: ServiceRecord) -> String {
    if let name = service.preferences.displayName, !name.isEmpty { return name }
    if let title = service.observation.http?.title, !title.isEmpty { return title }
    if let name = service.application?.name, !name.isEmpty { return name }
    if let framework = service.observation.framework, !framework.isEmpty { return framework }
    if let commandName = commandApplicationName(service), !commandName.isEmpty { return commandName }
    return service.process.name ?? "Web service :\(service.listener.port)"
}

func isOpenablePage(_ service: ServiceRecord) -> Bool {
    if service.preferences.classificationOverride == "page" { return true }
    if ["service", "listener"].contains(service.preferences.classificationOverride ?? "") { return false }
    if let role = service.observation.role { return role == "page" }
    guard let status = service.observation.http?.status else {
        return service.observation.classification == "suspected-web"
    }
    return (200..<400).contains(status)
}

/// A real, directly openable app should not disappear merely because it is not
/// attached to a Git checkout. Keep this deliberately stricter than the normal
/// page role so redirects and framework guesses remain in Other Web endpoints.
func isHighConfidenceStandalonePage(_ service: ServiceRecord) -> Bool {
    guard !service.relevance.developerRelevant,
          service.observation.classification == "confirmed-web",
          isOpenablePage(service),
          let status = service.observation.http?.status,
          (200..<300).contains(status),
          let title = service.observation.http?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
          !title.isEmpty,
          let contentType = service.observation.http?.contentType?.lowercased()
    else { return false }

    return contentType.contains("text/html") || contentType.contains("application/xhtml+xml")
}

func relatedServiceName(_ service: ServiceRecord) -> String {
    if let title = service.observation.http?.title, !title.isEmpty { return title }
    if let commandName = commandApplicationName(service), !commandName.isEmpty { return commandName }
    if let framework = service.observation.framework, !framework.isEmpty { return framework }
    return service.process.name ?? "service :\(service.listener.port)"
}

func relatedServiceDescription(_ service: ServiceRecord) -> String {
    if let status = service.observation.http?.status {
        if status == 404 { return "No homepage" }
        return "HTTP service · root \(status)"
    }
    if service.observation.classification == "suspected-web" {
        return "Likely Web service"
    }
    return "\(service.observation.protocol.uppercased()) service"
}

func serviceRenameKey(_ service: ServiceRecord) -> String {
    [
        service.project?.root,
        service.application?.root,
        service.application?.relativePath,
        String(service.listener.port),
    ].compactMap { $0 }.joined(separator: "|")
}

func projectIdentity(_ service: ServiceRecord) -> String {
    service.project?.root ?? service.application?.root ?? "process:\(service.process.pid)"
}

func applicationIdentity(_ service: ServiceRecord) -> String {
    service.application?.root ?? projectIdentity(service)
}

func groupServices(_ services: [ServiceRecord]) -> [ProjectGroup] {
    var projects: [ProjectGroup] = []
    for service in services {
        let projectID = projectIdentity(service)
        let projectIndex: Int
        if let existing = projects.firstIndex(where: { $0.id == projectID }) {
            projectIndex = existing
        } else {
            let name = service.project?.repositoryName
                ?? service.project?.name
                ?? service.application?.name
                ?? commandApplicationName(service)
                ?? "Unassigned Web app"
            projects.append(ProjectGroup(id: projectID, name: name, project: service.project, applications: []))
            projectIndex = projects.count - 1
        }

        let applicationID = applicationIdentity(service)
        if let appIndex = projects[projectIndex].applications.firstIndex(where: { $0.id == applicationID }) {
            projects[projectIndex].applications[appIndex].services.append(service)
        } else {
            let appName = service.application?.name
                ?? commandApplicationName(service)
                ?? projects[projectIndex].name
            projects[projectIndex].applications.append(ApplicationGroup(
                id: applicationID,
                name: appName,
                application: service.application,
                services: [service]
            ))
        }
    }
    for projectIndex in projects.indices {
        for applicationIndex in projects[projectIndex].applications.indices {
            projects[projectIndex].applications[applicationIndex].services.sort {
                $0.listener.port < $1.listener.port
            }
        }
    }
    return projects
}

func compactRemote(_ value: String?) -> String? {
    guard var remote = value, !remote.isEmpty else { return nil }
    if remote.hasPrefix("git@"), let colon = remote.firstIndex(of: ":") {
        let host = remote.dropFirst(4).prefix { $0 != ":" }
        remote = "\(host)/\(remote[remote.index(after: colon)...])"
    }
    remote = remote.replacingOccurrences(of: "https://", with: "")
    remote = remote.replacingOccurrences(of: "http://", with: "")
    if remote.hasSuffix(".git") { remote.removeLast(4) }
    return remote
}

func compactRepositoryLabel(_ value: String?) -> String? {
    guard var label = compactRemote(value) else { return nil }
    for prefix in ["github.com/", "gitlab.com/", "bitbucket.org/"] where label.hasPrefix(prefix) {
        label.removeFirst(prefix.count)
        break
    }
    return label
}

func repositoryWebURL(_ project: ProjectRecord?) -> URL? {
    guard let project, var remote = project.remoteUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !remote.isEmpty else {
        return nil
    }

    if remote.hasPrefix("git@"), let colon = remote.firstIndex(of: ":") {
        let host = remote.dropFirst(4).prefix { $0 != ":" }
        remote = "https://\(host)/\(remote[remote.index(after: colon)...])"
    } else if remote.hasPrefix("ssh://git@"), let url = URL(string: remote), let host = url.host {
        remote = "https://\(host)\(url.path)"
    }

    if remote.hasSuffix(".git") { remote.removeLast(4) }
    guard let repositoryURL = URL(string: remote), ["http", "https"].contains(repositoryURL.scheme?.lowercased() ?? "") else {
        return nil
    }

    guard repositoryURL.host?.lowercased() == "github.com",
          let branch = project.branch?.trimmingCharacters(in: .whitespacesAndNewlines),
          !branch.isEmpty else {
        return repositoryURL
    }
    return repositoryURL.appendingPathComponent("tree").appendingPathComponent(branch)
}

func worktreeLabel(_ project: ProjectRecord?) -> String? {
    guard let project, project.isWorktree == true else { return nil }
    let parent = URL(fileURLWithPath: project.root).deletingLastPathComponent().lastPathComponent
    return parent == project.name ? nil : parent
}

func compactPath(_ value: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return value.hasPrefix(home) ? "~" + value.dropFirst(home.count) : value
}

func serviceURL(_ service: ServiceRecord) -> URL? {
    let rawAddress = service.listener.address
    let address = ["0.0.0.0", "::", "*"].contains(rawAddress) ? "127.0.0.1" : rawAddress
    let host = address.contains(":") ? "[\(address)]" : address
    let scheme = service.observation.protocol == "https" ? "https" : "http"
    return URL(string: "\(scheme)://\(host):\(service.listener.port)")
}

func primaryServiceURL(_ service: ServiceRecord) -> URL? {
    if let value = service.route?.url, let routeURL = URL(string: value) { return routeURL }
    return serviceURL(service)
}

func compactServiceAddress(_ service: ServiceRecord) -> String {
    let value = primaryServiceURL(service)?.absoluteString ?? ":\(service.listener.port)"
    return value.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
}

func compactRawServiceAddress(_ service: ServiceRecord) -> String {
    let value = serviceURL(service)?.absoluteString ?? ":\(service.listener.port)"
    return value.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
}

func suggestedAlias(_ service: ServiceRecord) -> String {
    let source = service.application?.name ?? service.project?.name ?? serviceName(service)
    let latin = source.applyingTransform(.toLatin, reverse: false)?
        .applyingTransform(.stripDiacritics, reverse: false) ?? source
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
    let normalized = latin.lowercased().unicodeScalars.map { scalar -> Character in
        allowed.contains(scalar) ? Character(String(scalar)) : "-"
    }
    let collapsed = String(normalized).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
    let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return String((trimmed.isEmpty ? "local-app" : trimmed).prefix(63)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

func listenerEndpoint(_ service: ServiceRecord) -> String {
    let address = service.listener.address
    let host = address.contains(":") && address != "::" ? "[\(address)]" : address
    return "\(host):\(service.listener.port)"
}

func relativeAge(_ value: String?) -> String? {
    guard let value else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
    guard let date = formatter.date(from: value) else { return nil }
    let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
    if minutes < 1 { return "<1m" }
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h \(minutes % 60)m" }
    return "\(hours / 24)d \(hours % 24)h"
}

func serviceSearchText(_ service: ServiceRecord) -> String {
    [
        serviceName(service),
        String(service.listener.port),
        service.listener.address,
        service.project?.name,
        service.project?.branch,
        service.project?.root,
        service.project?.remoteUrl,
        service.application?.name,
        service.application?.relativePath,
        service.process.command,
        service.route?.alias,
        service.route?.url,
    ].compactMap { $0 }.joined(separator: " ").lowercased()
}

func serviceTypeDescription(_ service: ServiceRecord) -> String {
    if isOpenablePage(service) { return "Openable Web page" }
    if service.observation.classification == "confirmed-web" { return "Background HTTP service" }
    if service.observation.classification == "suspected-web" { return "Likely Web service" }
    return "TCP listener"
}

func homepageDescription(_ service: ServiceRecord) -> String {
    guard let status = service.observation.http?.status else { return "Not verified" }
    if status == 404 { return "Not provided (HTTP 404)" }
    if (200..<400).contains(status) { return "Available (HTTP \(status))" }
    return "Returns HTTP \(status)"
}

func detectionDescription(_ service: ServiceRecord) -> String {
    if service.observation.evidence.contains(where: { $0.kind == "valid-http-response" }) {
        return "Responds to HTTP"
    }
    if service.observation.classification == "suspected-web" {
        return "Process resembles a Web service"
    }
    return "Active local listener"
}

func secondaryServiceName(_ service: ServiceRecord) -> String {
    if webClassifications.contains(service.observation.classification) {
        return isOpenablePage(service) ? serviceName(service) : relatedServiceName(service)
    }
    if let commandName = commandApplicationName(service), !commandName.isEmpty { return commandName }
    return service.process.name ?? "Listener :\(service.listener.port)"
}

func secondaryServiceDescription(_ service: ServiceRecord) -> String {
    if webClassifications.contains(service.observation.classification) {
        if isOpenablePage(service) { return "Web page" }
        return relatedServiceDescription(service)
    }
    if service.observation.protocol == "unknown" { return "Unverified listener" }
    return "\(service.observation.protocol.uppercased()) listener"
}

struct ServiceDetailRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(size: 11, design: .monospaced) : .system(size: 11))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11))
    }
}

private let detailNavigationAnimation = Animation.snappy(duration: 0.18, extraBounce: 0.025)

private struct NavigationBackButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct ServiceDetailView: View {
    let service: ServiceRecord
    let onBack: () -> Void
    let onReviewStop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollIndicator = ScrollIndicatorMetrics()
    @State private var backHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.primary.opacity(backHovered ? 0.96 : 0.82))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(
                        Color.secondary.opacity(backHovered ? 0.105 : 0),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(NavigationBackButtonStyle(reduceMotion: reduceMotion))
                .keyboardShortcut(.cancelAction)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.1)) { backHovered = hovering }
                }
                .help("Back (Esc or ⌘[)")
                .accessibilityLabel("Back to Web apps")
                Spacer()
                Text("Service details")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 42, height: 1)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isOpenablePage(service) ? serviceName(service) : relatedServiceName(service))
                            .font(.system(size: 18, weight: .semibold))
                        Text(serviceTypeDescription(service))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("OVERVIEW")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        if webClassifications.contains(service.observation.classification) {
                            ServiceDetailRow(label: "Homepage", value: homepageDescription(service))
                        }
                        ServiceDetailRow(label: "Shown because", value: detectionDescription(service))
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("ENDPOINT")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        if webClassifications.contains(service.observation.classification) {
                            ServiceDetailRow(label: "Local", value: serviceURL(service)?.absoluteString ?? "Unknown", monospaced: true)
                        }
                        ServiceDetailRow(label: "Listening", value: listenerEndpoint(service), monospaced: true)
                        ServiceDetailRow(
                            label: "Network",
                            value: service.listener.bindScope == "loopback" ? "This Mac only" : "Available on your local network"
                        )
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("PROCESS")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        ServiceDetailRow(label: "Project", value: service.project?.name ?? "Unassigned")
                        ServiceDetailRow(
                            label: "Application",
                            value: service.application?.name ?? commandApplicationName(service) ?? "Project root"
                        )
                        ServiceDetailRow(label: "Command", value: service.process.command ?? "Unknown", monospaced: true)
                    }

                    Button("Review safe stop…", systemImage: "stop.circle", action: onReviewStop)
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
                .padding(18)
                .background(TransientScrollViewConfigurator(metrics: $scrollIndicator))
            }
            .scrollIndicators(.hidden)
            .contentMargins(.trailing, 0, for: .scrollContent)
            .overlay(alignment: .topTrailing) {
                TransientScrollIndicator(metrics: scrollIndicator)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onKeyPress("[", phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            onBack()
            return .handled
        }
    }
}

enum RenameKind: Equatable {
    case project
    case service
}

struct RenameTarget: Identifiable {
    let id = UUID()
    let key: String
    let kind: RenameKind
    let currentName: String
}

struct StopReview: Identifiable {
    let id = UUID()
    let service: ServiceRecord
    let plan: StopPlanRecord
}

struct ForceStopReview: Identifiable {
    let id = UUID()
    let service: ServiceRecord
    let plan: ForceStopPlanRecord
}

struct StopConfirmationView: View {
    let review: StopReview
    @Binding var isStopping: Bool
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var isEligible: Bool {
        review.plan.decision == "eligible" && review.plan.planToken != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isEligible ? "stop.circle.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isEligible ? .red : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isEligible ? "Stop this service?" : "Cannot stop this service safely")
                        .font(.headline)
                    Text("Port Tools revalidates this exact process tree before sending SIGTERM.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ServiceDetailRow(label: "Service", value: serviceName(review.service))
                ServiceDetailRow(label: "Root PID", value: String(review.plan.rootProcess.pid), monospaced: true)
                ServiceDetailRow(
                    label: "Signal order",
                    value: review.plan.gracefulPlan.pids.map(String.init).joined(separator: " → ").isEmpty
                        ? "None"
                        : review.plan.gracefulPlan.pids.map(String.init).joined(separator: " → "),
                    monospaced: true
                )
                ServiceDetailRow(
                    label: "Verify",
                    value: review.plan.gracefulPlan.verifyListenersReleased
                        .map { "\($0.address):\($0.port)" }
                        .joined(separator: ", "),
                    monospaced: true
                )
            }

            if !review.plan.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("WHY IT WAS REFUSED")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    ForEach(review.plan.reasons, id: \.self) { reason in
                        Label(reason, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !review.plan.exclusions.isEmpty {
                Text("\(review.plan.exclusions.count) related process(es) are excluded because ownership could not be proven.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(isEligible ? "Cancel" : "Done") { dismiss() }
                    .disabled(isStopping)
                if isEligible {
                    Button("Stop service", role: .destructive) { onConfirm() }
                        .disabled(isStopping)
                }
            }
        }
        .padding(18)
        .frame(width: 430)
        .overlay {
            if isStopping {
                ProgressView("Revalidating and stopping…")
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .interactiveDismissDisabled(isStopping)
    }
}

struct ForceStopConfirmationView: View {
    let review: ForceStopReview
    @Binding var isStopping: Bool
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var secondsRemaining = 3

    private var isEligible: Bool {
        review.plan.decision == "eligible" && review.plan.planToken != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isEligible ? "Force stop this service?" : "Force stop refused")
                        .font(.headline)
                    Text("SIGKILL cannot be handled or postponed by the app. Port Tools will revalidate every PID and listener again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ServiceDetailRow(
                    label: "PID order",
                    value: review.plan.processes.map { String($0.pid) }.joined(separator: " → "),
                    monospaced: true
                )
                ServiceDetailRow(
                    label: "Listeners",
                    value: review.plan.verifyListenersReleased.map { "\($0.address):\($0.port)" }.joined(separator: ", "),
                    monospaced: true
                )
            }

            ForEach(review.plan.reasons, id: \.self) { reason in
                Label(reason, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(isEligible ? "Cancel" : "Done") { dismiss() }
                    .disabled(isStopping)
                if isEligible {
                    Button(secondsRemaining > 0 ? "Force stop in \(secondsRemaining)…" : "Force stop now", role: .destructive) {
                        onConfirm()
                    }
                    .disabled(isStopping || secondsRemaining > 0)
                }
            }
        }
        .padding(18)
        .frame(width: 450)
        .interactiveDismissDisabled(isStopping)
        .task {
            while secondsRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                secondsRemaining -= 1
            }
        }
    }
}

struct RenameView: View {
    let target: RenameTarget
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(target: RenameTarget, onSave: @escaping (String) -> Void) {
        self.target = target
        self.onSave = onSave
        _name = State(initialValue: target.currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.kind == .project ? "Rename project" : "Rename service")
                        .font(.headline)
                    Text("This changes its display name in Port Tools.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            TextField("Display name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { save() }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
    }

    private func save() {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onSave(value)
        dismiss()
    }
}

private let disclosureAnimation = Animation.snappy(duration: 0.17, extraBounce: 0.035)
private let disclosureContentTransition = AnyTransition.asymmetric(
    insertion: .offset(y: -4).combined(with: .opacity),
    removal: .opacity
)
let inventoryPanelWidth: CGFloat = 382
let inventoryPanelHeight: CGFloat = 640

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return portToolsString("System")
        case .light: return portToolsString("Light")
        case .dark: return portToolsString("Dark")
        }
    }
}

private enum PortToolsTheme {
    static func panelBase(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.075, green: 0.086, blue: 0.112)
            : Color(red: 0.955, green: 0.966, blue: 0.982)
    }

    static func chromeSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.025) : Color.white.opacity(0.46)
    }

    static func headerSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.72)
    }

    static func groupSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.52)
    }

    static func groupBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.78)
    }

    static func hoverSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.035)
    }
}

private struct FullTitleBubble: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    private var tooltipWidth: CGFloat {
        min(310, max(150, CGFloat(title.count) * 6.6))
    }

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: tooltipWidth, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                PortToolsTheme.panelBase(colorScheme),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(PortToolsTheme.groupBorder(colorScheme), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 9, y: 4)
            .allowsHitTesting(false)
    }
}

private struct TitleRenderedWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HoverFullTitleText: View {
    let title: String
    let font: Font
    let nsFont: NSFont
    var isUnderlined = false

    @State private var renderedWidth: CGFloat = 0
    @State private var pointerIsInside = false
    @State private var isVisible = false
    @State private var pendingReveal: DispatchWorkItem?

    private var idealWidth: CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: nsFont]).width)
    }

    private var isTruncated: Bool {
        renderedWidth > 0 && idealWidth > renderedWidth + 1
    }

    private var forcesTooltipForPreview: Bool {
        CommandLine.arguments.contains("--preview-window")
            && ProcessInfo.processInfo.environment["PORT_TOOLS_PREVIEW_FULL_TITLE"] == "1"
            && isTruncated
    }

    var body: some View {
        Text(title)
            .font(font)
            .lineLimit(1)
            .truncationMode(.tail)
            .underline(isUnderlined)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: TitleRenderedWidthPreferenceKey.self,
                        value: geometry.size.width
                    )
                }
            )
            .contentShape(Rectangle())
            .overlay {
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Rectangle())
                    .onHover(perform: handleHover)
            }
            .onPreferenceChange(TitleRenderedWidthPreferenceKey.self) { width in
                renderedWidth = width
                if !isTruncated {
                    pendingReveal?.cancel()
                    pendingReveal = nil
                    isVisible = false
                }
            }
            .overlay(alignment: .topLeading) {
                if isVisible || forcesTooltipForPreview {
                    FullTitleBubble(title: title)
                        .offset(x: -4, y: -3)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }
            }
            .zIndex(isVisible || forcesTooltipForPreview ? 100 : 0)
            .onDisappear {
                pendingReveal?.cancel()
                pendingReveal = nil
            }
    }

    private func handleHover(_ hovering: Bool) {
        pointerIsInside = hovering
        pendingReveal?.cancel()
        pendingReveal = nil

        if hovering && isTruncated {
            let reveal = DispatchWorkItem {
                guard pointerIsInside, isTruncated else { return }
                withAnimation(.easeOut(duration: 0.12)) { isVisible = true }
            }
            pendingReveal = reveal
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: reveal)
        } else {
            withAnimation(.easeOut(duration: 0.08)) { isVisible = false }
        }
    }
}

struct DisclosureRow<Content: View>: View {
    let isExpanded: Bool
    let isEnabled: Bool
    let animatesContent: Bool
    let level: Int
    let contentInsets: EdgeInsets
    let minimumHeight: CGFloat
    let contentSpacing: CGFloat?
    let trailingChevron: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        isExpanded: Bool,
        isEnabled: Bool = true,
        animatesContent: Bool = true,
        level: Int = 0,
        contentInsets: EdgeInsets,
        minimumHeight: CGFloat = 0,
        contentSpacing: CGFloat? = nil,
        trailingChevron: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isExpanded = isExpanded
        self.isEnabled = isEnabled
        self.animatesContent = animatesContent
        self.level = level
        self.contentInsets = contentInsets
        self.minimumHeight = minimumHeight
        self.contentSpacing = contentSpacing
        self.trailingChevron = trailingChevron
        self.action = action
        self.content = content
    }

    private var chevronOpacity: Double {
        if isHovered { return 0.58 }
        return isExpanded ? 0.34 : 0.14
    }

    private var hoverOpacity: Double {
        level == 0 ? 0.055 : 0.04
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: level == 0 ? 8.5 : 8, weight: .semibold))
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .foregroundStyle(Color.secondary.opacity(chevronOpacity))
            .frame(width: level == 0 ? 14 : 12)
            .animation(disclosureAnimation, value: isExpanded)
    }

    var body: some View {
        Button {
            guard isEnabled else { return }
            if animatesContent {
                withAnimation(disclosureAnimation) { action() }
            } else {
                action()
            }
        } label: {
            HStack(spacing: contentSpacing ?? (level == 0 ? 7 : 8)) {
                if !trailingChevron { chevron }
                content()
                if trailingChevron { chevron }
            }
            .contentShape(Rectangle())
            .padding(contentInsets)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
            .background(
                PortToolsTheme.hoverSurface(colorScheme).opacity(isHovered && isEnabled ? 1 : 0),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

private struct ExpandableContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Keeps secondary-section width stable while giving the content a compact,
/// direction-aware reveal inspired by React Bits' Animated Content pattern.
struct ExpandableContent<Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = 0

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .snappy(duration: 0.2, extraBounce: 0.035)
    }

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: ExpandableContentHeightKey.self, value: geometry.size.height)
                }
            }
            .opacity(isExpanded ? 1 : 0)
            .offset(y: reduceMotion || isExpanded ? 0 : -5)
            .scaleEffect(x: 1, y: reduceMotion || isExpanded ? 1 : 0.985, anchor: .top)
            .frame(height: isExpanded ? contentHeight : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
            .animation(animation, value: isExpanded)
            .onPreferenceChange(ExpandableContentHeightKey.self) { measuredHeight in
                guard measuredHeight > 0, abs(measuredHeight - contentHeight) > 0.5 else { return }
                contentHeight = measuredHeight
            }
    }
}

struct WindowFrameReader: NSViewRepresentable {
    let onChange: (Int?, CGRect) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            onChange(view.window?.windowNumber, view.convert(view.bounds, to: nil))
        }
    }
}

struct ScrollIndicatorMetrics: Equatable {
    var offset: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var contentHeight: CGFloat = 0
    var isVisible = false
}

/// Removes AppKit's layout-affecting scroller entirely and reports scroll
/// activity so SwiftUI can draw a transient, non-layout overlay indicator.
struct TransientScrollViewConfigurator: NSViewRepresentable {
    @Binding var metrics: ScrollIndicatorMetrics

    func makeCoordinator() -> Coordinator {
        Coordinator(metrics: $metrics)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.metrics = $metrics
        configure(view, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    private func configure(_ view: NSView, coordinator: Coordinator, attemptsRemaining: Int = 8) {
        DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else {
                guard attemptsRemaining > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    configure(view, coordinator: coordinator, attemptsRemaining: attemptsRemaining - 1)
                }
                return
            }

            scrollView.hasVerticalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.tile()
            coordinator.attach(to: scrollView)
        }
    }

    final class Coordinator {
        var metrics: Binding<ScrollIndicatorMetrics>
        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var liveScrollObserver: NSObjectProtocol?
        private var endScrollObserver: NSObjectProtocol?
        private var hideWorkItem: DispatchWorkItem?
        private var lastOffset: CGFloat?

        init(metrics: Binding<ScrollIndicatorMetrics>) {
            self.metrics = metrics
        }

        func attach(to scrollView: NSScrollView) {
            if self.scrollView === scrollView {
                return
            }

            detach()
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true

            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.publish(revealWhenOffsetChanges: true)
            }
            liveScrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                self?.publish(reveal: true)
            }
            endScrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleHide()
            }
            publish(reveal: false)
        }

        func detach() {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            for observer in [boundsObserver, liveScrollObserver, endScrollObserver].compactMap({ $0 }) {
                NotificationCenter.default.removeObserver(observer)
            }
            boundsObserver = nil
            liveScrollObserver = nil
            endScrollObserver = nil
            scrollView = nil
            lastOffset = nil
        }

        private func publish(revealWhenOffsetChanges: Bool) {
            guard let scrollView else { return }
            let offset = max(0, scrollView.contentView.bounds.minY)
            let offsetChanged = lastOffset.map { abs($0 - offset) > 0.5 } ?? false
            if revealWhenOffsetChanges && offsetChanged {
                publish(reveal: true)
            } else {
                publish(reveal: metrics.wrappedValue.isVisible, scheduleHideAfterReveal: false)
            }
        }

        private func publish(reveal: Bool, scheduleHideAfterReveal: Bool = true) {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let viewportHeight = scrollView.contentView.bounds.height
            let contentHeight = documentView.bounds.height
            let offset = max(0, scrollView.contentView.bounds.minY)
            let canScroll = contentHeight > viewportHeight + 1
            let next = ScrollIndicatorMetrics(
                offset: offset,
                viewportHeight: viewportHeight,
                contentHeight: contentHeight,
                isVisible: reveal && canScroll
            )
            if metrics.wrappedValue != next {
                metrics.wrappedValue = next
            }
            lastOffset = offset
            if reveal && canScroll && scheduleHideAfterReveal {
                scheduleHide()
            }
        }

        fileprivate func scheduleHide() {
            hideWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                var next = metrics.wrappedValue
                next.isVisible = false
                if metrics.wrappedValue != next {
                    metrics.wrappedValue = next
                }
            }
            hideWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: item)
        }
    }
}

struct TransientScrollIndicator: View {
    let metrics: ScrollIndicatorMetrics

    var body: some View {
        GeometryReader { geometry in
            let trackHeight = max(0, geometry.size.height - 8)
            let ratio = metrics.contentHeight > 0 ? min(1, metrics.viewportHeight / metrics.contentHeight) : 1
            let thumbHeight = min(trackHeight, max(28, trackHeight * ratio))
            let maximumOffset = max(1, metrics.contentHeight - metrics.viewportHeight)
            let progress = min(1, max(0, metrics.offset / maximumOffset))
            let thumbOffset = 4 + ((trackHeight - thumbHeight) * progress)

            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 3, height: thumbHeight)
                .offset(x: geometry.size.width - 7, y: thumbOffset)
                .opacity(metrics.isVisible && ratio < 1 ? 1 : 0)
                .animation(.easeOut(duration: 0.16), value: metrics.isVisible)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ProjectTitleLink: View {
    let title: String
    let destination: URL?

    @State private var isHovered = false

    var body: some View {
        Group {
            if let destination {
                Button {
                    NSWorkspace.shared.open(destination)
                } label: {
                    HStack(spacing: 3) {
                        HoverFullTitleText(
                            title: title,
                            font: .system(size: 13, weight: .semibold),
                            nsFont: .systemFont(ofSize: 13, weight: .semibold),
                            isUnderlined: isHovered
                        )
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundStyle(Color.secondary.opacity(isHovered ? 0.52 : 0))
                            .frame(width: 9)
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
                }
                .help("Open the current repository branch")
                .accessibilityLabel("\(title), open current repository branch")
            } else {
                HoverFullTitleText(
                    title: title,
                    font: .system(size: 13, weight: .semibold),
                    nsFont: .systemFont(ofSize: 13, weight: .semibold)
                )
            }
        }
    }
}

struct BackgroundServiceButton: View {
    let count: Int
    let isExpanded: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(disclosureAnimation) { action() }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 8.5, weight: .medium))
                if count > 1 {
                    Text(String(count))
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .foregroundStyle(Color.secondary.opacity(isHovered || isExpanded ? 0.78 : 0.5))
            .padding(.horizontal, 4)
            .frame(minWidth: 22, minHeight: 18)
            .background(
                Color.secondary.opacity(isHovered || isExpanded ? 0.12 : 0.065),
                in: Capsule()
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
        }
        .help("\(count) background service\(count == 1 ? "" : "s"). Click to \(isExpanded ? "hide" : "show").")
        .accessibilityLabel("\(count) background service\(count == 1 ? "" : "s")")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

private struct RuntimeAgeLabel: View {
    let age: String

    var body: some View {
        Text(age)
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 40, alignment: .trailing)
            .help("Process has been running for \(age)")
    }
}

struct ServiceRow: View {
    @ObservedObject private var portless = PortlessServiceController.shared
    let service: ServiceRecord
    let displayName: String
    let projectContext: String?
    let repositoryURL: URL?
    let backgroundServiceCount: Int
    let backgroundServicesExpanded: Bool
    let fillsProjectCard: Bool
    let onToggleBackgroundServices: (() -> Void)?
    let onRename: () -> Void
    let onRenameProject: (() -> Void)?
    let onSaveAlias: (String) -> Void
    let onRemoveAlias: (() -> Void)?
    let onEvidence: () -> Void
    let onReviewStop: () -> Void
    let onTogglePin: () -> Void
    let onIgnore: () -> Void
    let onClassification: (String) -> Void
    let onMessage: (String) -> Void

    @State private var isHovered = false
    @State private var isLinkHovered = false
    @State private var isEditingAlias = false
    @State private var aliasDraft = ""
    @State private var aliasEditorDidFocus = false
    @State private var aliasEditorFrame = CGRect.zero
    @State private var aliasEditorWindowNumber: Int?
    @State private var aliasClickMonitor: Any?
    @FocusState private var aliasFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var normalizedAlias: String {
        aliasDraft.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var aliasIsValid: Bool {
        normalizedAlias.range(of: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"#, options: .regularExpression) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                ProjectTitleLink(title: displayName, destination: repositoryURL)
                    .font(.system(size: 13, weight: .semibold))

                if service.observation.classification == "suspected-web" {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange.opacity(0.75))
                        .help("Web detection is not yet verified")
                } else {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green.opacity(0.72))
                        .help("HTTP or HTTPS response verified")
                }
                if service.preferences.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.blue)
                        .help("Pinned")
                }
                if service.staleness.possiblyForgotten {
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .help("Possibly forgotten: \(service.staleness.reasons.joined(separator: ", "))")
                }
                if backgroundServiceCount > 0, let onToggleBackgroundServices {
                    BackgroundServiceButton(
                        count: backgroundServiceCount,
                        isExpanded: backgroundServicesExpanded,
                        action: onToggleBackgroundServices
                    )
                }
                Spacer(minLength: 4)
                if let age = relativeAge(service.process.started) {
                    RuntimeAgeLabel(age: age)
                }

                Menu {
                    Button("Copy address", systemImage: "doc.on.doc") { copyAddress() }
                    if service.route != nil {
                        Button("Open original address", systemImage: "arrow.up.right.square") {
                            openOriginalAddress()
                        }
                        Button("Copy original address", systemImage: "doc.on.doc") {
                            copyOriginalAddress()
                        }
                    }
                    Button("Rename display name…", systemImage: "pencil", action: onRename)
                    Button(service.preferences.pinned ? "Unpin" : "Pin", systemImage: service.preferences.pinned ? "pin.slash" : "pin", action: onTogglePin)
                    if let onRenameProject {
                        Button("Rename project…", systemImage: "folder.badge.gearshape", action: onRenameProject)
                    }
                    Divider()
                    Button(
                        service.route == nil ? "Add local address…" : "Edit local address…",
                        systemImage: service.route == nil ? "link.badge.plus" : "link"
                    ) { beginAliasEditing() }
                    if let onRemoveAlias {
                        Button("Remove local address", systemImage: "link.badge.minus", role: .destructive, action: onRemoveAlias)
                    }
                    Button("Why this was detected", systemImage: "info.circle", action: onEvidence)
                    Menu("Display as") {
                        Button("Automatic") { onClassification("auto") }
                        Button("Page") { onClassification("page") }
                        Button("Service") { onClassification("service") }
                        Button("Listener") { onClassification("listener") }
                    }
                    Button("Review safe stop…", systemImage: "stop.circle", action: onReviewStop)
                    Divider()
                    Button("Ignore", systemImage: "eye.slash", action: onIgnore)
                    if let path = service.project?.root {
                        Divider()
                        Button("Reveal project in Finder", systemImage: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                        Button("Copy project path", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(path, forType: .string)
                            onMessage("Project path copied")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(isHovered ? 0.58 : 0.2))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if let projectContext {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(projectContext)
                        .lineLimit(1)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            }

            if isEditingAlias {
                HStack(spacing: 5) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        TextField("project-name", text: $aliasDraft)
                            .textFieldStyle(.plain)
                            .focused($aliasFocused)
                            .onSubmit { saveAlias() }
                        Text(portless.runtimeStatus == .active ? ".localhost" : ".localhost:17890")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 7)
                    .frame(height: 26)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(aliasIsValid ? Color.accentColor.opacity(0.45) : Color.red.opacity(0.65))
                    )
                    .background(
                        WindowFrameReader { windowNumber, frame in
                            aliasEditorWindowNumber = windowNumber
                            aliasEditorFrame = frame
                        }
                    )
                    .onChange(of: aliasFocused) { _, focused in
                        if focused {
                            aliasEditorDidFocus = true
                        } else {
                            saveAliasWhenFocusLeaves()
                        }
                    }
                }
                .onExitCommand { cancelAliasEditing() }
                .help("Press Return or click elsewhere to save. Press Escape to cancel.")
            } else {
                HStack(spacing: 5) {
                    Button {
                        if let url = primaryServiceURL(service) { NSWorkspace.shared.open(url) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "link")
                            Text(compactServiceAddress(service))
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                                .underline(isLinkHovered)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .onHover { isLinkHovered = $0 }
                    .help("Open in browser")

                    Button { beginAliasEditing() } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(Color.secondary.opacity(isHovered ? 0.72 : 0.38))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(service.route == nil ? "Add stable local address" : "Edit local address")

                    if service.listener.bindScope != "loopback" {
                        Image(systemName: "network")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .help("Potentially reachable on this LAN")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHovered ? PortToolsTheme.hoverSurface(colorScheme) : Color.clear,
            in: RoundedRectangle(cornerRadius: fillsProjectCard ? 12 : 8, style: .continuous)
        )
        .zIndex(isHovered ? 5 : 0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
        }
        .onDisappear {
            removeAliasClickMonitor()
        }
    }

    private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(primaryServiceURL(service)?.absoluteString ?? "", forType: .string)
        onMessage("Address copied")
    }

    private func openOriginalAddress() {
        if let url = serviceURL(service) { NSWorkspace.shared.open(url) }
    }

    private func copyOriginalAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(serviceURL(service)?.absoluteString ?? "", forType: .string)
        onMessage(portToolsString("Original address copied"))
    }

    private func beginAliasEditing() {
        aliasDraft = service.route?.alias ?? suggestedAlias(service)
        aliasEditorDidFocus = false
        isEditingAlias = true
        DispatchQueue.main.async {
            aliasFocused = true
            installAliasClickMonitor()
        }
    }

    private func cancelAliasEditing() {
        removeAliasClickMonitor()
        aliasEditorDidFocus = false
        isEditingAlias = false
        aliasFocused = false
    }

    private func saveAlias() {
        guard aliasIsValid else { return }
        removeAliasClickMonitor()
        aliasEditorDidFocus = false
        isEditingAlias = false
        aliasFocused = false
        onSaveAlias(normalizedAlias)
    }

    private func saveAliasWhenFocusLeaves() {
        guard isEditingAlias, aliasEditorDidFocus else { return }
        if aliasIsValid {
            saveAlias()
        } else {
            onMessage("Use lowercase letters, numbers, and hyphens")
            DispatchQueue.main.async { aliasFocused = true }
        }
    }

    private func installAliasClickMonitor() {
        guard aliasClickMonitor == nil else { return }
        aliasClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            let isInsideEditor = event.windowNumber == aliasEditorWindowNumber
                && aliasEditorFrame.contains(event.locationInWindow)
            if !isInsideEditor {
                DispatchQueue.main.async { saveAliasWhenFocusLeaves() }
            }
            return event
        }
    }

    private func removeAliasClickMonitor() {
        guard let monitor = aliasClickMonitor else { return }
        NSEvent.removeMonitor(monitor)
        aliasClickMonitor = nil
    }
}

struct RelatedServiceRow: View {
    let service: ServiceRecord
    let parentName: String
    let onEvidence: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onEvidence) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 13, height: 16)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(relatedServiceName(service))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        if service.listener.bindScope != "loopback" {
                            Label("LAN access", systemImage: "network")
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    HStack(spacing: 4) {
                        Text("Supporting service")
                        Text("·")
                        Text(relatedServiceDescription(service))
                        Text("·")
                        Text(compactRawServiceAddress(service))
                            .font(.system(size: 9, design: .monospaced))
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    if let age = relativeAge(service.process.started) {
                        RuntimeAgeLabel(age: age)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(isHovered ? 0.58 : 0.08))
                        .frame(width: 10, height: 16)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(
            isHovered ? PortToolsTheme.hoverSurface(colorScheme) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
        }
        .accessibilityLabel("\(relatedServiceName(service)), supporting service for \(parentName)")
        .help("Supporting service for \(parentName). Click for details.")
    }
}

struct SecondaryServiceRow: View {
    let service: ServiceRecord
    let onDetails: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onDetails) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(secondaryServiceName(service))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(secondaryServiceDescription(service))
                        Text("·")
                        Text(listenerEndpoint(service))
                            .font(.system(size: 9, design: .monospaced))
                        if service.listener.bindScope != "loopback" {
                            Text("· LAN access")
                        }
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let age = relativeAge(service.process.started) {
                    RuntimeAgeLabel(age: age)
                }
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .background(
            isHovered ? PortToolsTheme.hoverSurface(colorScheme) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
        }
        .help("Show details")
    }
}

struct InventoryView: View {
    @ObservedObject var store: InventoryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.dark.rawValue
    @State private var expandedRelated = Set<String>()
    @State private var collapsedProjects = Set<String>()
    @State private var expandedOtherWeb = false
    @State private var expandedOtherListeners = false
    @State private var evidenceService: ServiceRecord?
    @State private var renameTarget: RenameTarget?
    @State private var stopReview: StopReview?
    @State private var forceStopReview: ForceStopReview?
    @State private var stopInProgress = false
    @State private var projectNames = UserDefaults.standard.dictionary(forKey: "projectDisplayNames") as? [String: String] ?? [:]
    @State private var serviceNames = UserDefaults.standard.dictionary(forKey: "serviceDisplayNames") as? [String: String] ?? [:]
    @State private var pinnedProjects = Set(UserDefaults.standard.stringArray(forKey: "pinnedProjectIDs") ?? [])
    @State private var query = ""
    @State private var searchVisible = false
    @State private var message: String?
    @State private var scrollIndicator = ScrollIndicatorMetrics()
    @FocusState private var searchFocused: Bool

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var allServices: [ServiceRecord] {
        (store.document?.services ?? [])
            .filter { !$0.preferences.ignored }
            .sorted {
                if $0.preferences.pinned != $1.preferences.pinned { return $0.preferences.pinned }
                return $0.listener.port < $1.listener.port
            }
    }
    private var webServices: [ServiceRecord] {
        allServices.filter {
            if $0.preferences.classificationOverride == "listener" { return false }
            if ["page", "service"].contains($0.preferences.classificationOverride ?? "") { return true }
            return webClassifications.contains($0.observation.classification)
        }
    }
    private var primaryWebServices: [ServiceRecord] {
        webServices.filter { $0.relevance.developerRelevant || isHighConfidenceStandalonePage($0) }
    }
    private var developmentPages: [ServiceRecord] {
        primaryWebServices.filter(isOpenablePage)
    }
    private var projects: [ProjectGroup] {
        groupServices(primaryWebServices)
            .filter { $0.services.contains(where: isOpenablePage) }
            .sorted {
                let leftPinned = pinnedProjects.contains($0.id)
                let rightPinned = pinnedProjects.contains($1.id)
                if leftPinned != rightPinned { return leftPinned }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
    private var displayedProjectServiceIDs: Set<String> {
        Set(projects.flatMap(\.services).map(\.id))
    }
    private var otherWebServices: [ServiceRecord] {
        webServices.filter { !displayedProjectServiceIDs.contains($0.id) }
    }
    private var otherListenerServices: [ServiceRecord] {
        allServices.filter { service in
            service.preferences.classificationOverride == "listener" ||
                (!["page", "service"].contains(service.preferences.classificationOverride ?? "") &&
                    !webClassifications.contains(service.observation.classification))
        }
    }
    private var searchNeedle: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var isSearching: Bool { !searchNeedle.isEmpty }
    private var preferredColorScheme: ColorScheme? {
        switch AppearanceMode(rawValue: appearanceModeRaw) ?? .dark {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    private var inventorySummary: String {
        let projectCount = Set(developmentPages.compactMap { $0.project?.root }).count
        let projectLabel = projectCount == 1 ? "project" : "projects"
        let appLabel = developmentPages.count == 1 ? "Web app" : "Web apps"
        guard projectCount > 0 else { return "\(developmentPages.count) \(appLabel)" }
        return "\(projectCount) \(projectLabel) · \(developmentPages.count) \(appLabel)"
    }
    private var filteredOtherWebServices: [ServiceRecord] {
        guard isSearching else { return otherWebServices }
        return otherWebServices.filter { serviceSearchText($0).contains(searchNeedle) }
    }
    private var filteredOtherListenerServices: [ServiceRecord] {
        guard isSearching else { return otherListenerServices }
        return otherListenerServices.filter { serviceSearchText($0).contains(searchNeedle) }
    }

    private var filteredProjects: [ProjectGroup] {
        let needle = searchNeedle
        guard !needle.isEmpty else { return projects }
        return projects.compactMap { project in
            let projectText = [project.name, projectNames[project.id], project.project?.branch, project.project?.root, project.project?.remoteUrl]
                .compactMap { $0 }.joined(separator: " ").lowercased()
            if projectText.contains(needle) { return project }

            var matched = project
            matched.applications = project.applications.compactMap { application in
                let appText = [application.name, application.application?.relativePath, application.application?.manifest]
                    .compactMap { $0 }.joined(separator: " ").lowercased()
                if appText.contains(needle) { return application }
                var filtered = application
                filtered.services = application.services.filter {
                    serviceSearchText($0).contains(needle)
                        || serviceNames[serviceRenameKey($0)]?.lowercased().contains(needle) == true
                }
                return filtered.services.isEmpty ? nil : filtered
            }
            return matched.applications.isEmpty ? nil : matched
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text("Port Tools").font(.system(size: 18, weight: .bold))
                        HStack(spacing: 5) {
                            Circle().fill(Color.green).frame(width: 5, height: 5)
                            Text("LIVE")
                        }
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(Color.green.opacity(colorScheme == .dark ? 0.12 : 0.09), in: Capsule())
                    }
                    Text(store.document == nil ? "Scanning local Web apps…" : inventorySummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    searchVisible.toggle()
                    if searchVisible { searchFocused = true } else { query = "" }
                } label: { Image(systemName: "magnifyingglass") }
                    .help("Search (⌘K)")
                Button { store.refresh() } label: {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .help("Refresh")
                Menu {
                    Picker("Appearance", selection: $appearanceModeRaw) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    Divider()
                    SettingsLink { Text("Settings…") }
                    Button("Quit Port Tools") { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "gearshape") }
                .menuIndicator(.hidden)
                .help("Settings")
                .accessibilityLabel("Settings")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(PortToolsTheme.headerSurface(colorScheme))

            if searchVisible {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Project, app, port, branch…", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(PortToolsTheme.groupSurface(colorScheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.6)))
                .shadow(color: Color.blue.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 8, y: 2)
                .padding(.horizontal, 10)
                .padding(.bottom, 7)
            }

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let error = store.errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Live scan unavailable").font(.caption.weight(.semibold))
                                Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                            }
                            Spacer()
                            Button("Retry") { store.refresh() }.controlSize(.small)
                        }
                        .padding(12)
                    } else if store.document == nil {
                        ProgressView("Checking active Web services…")
                            .controlSize(.small)
                            .padding(.vertical, 80)
                    } else if filteredProjects.isEmpty && filteredOtherWebServices.isEmpty && filteredOtherListenerServices.isEmpty {
                        ContentUnavailableView(
                            query.isEmpty ? "No development Web apps" : "No matching Web apps",
                            systemImage: "magnifyingglass",
                            description: Text(query.isEmpty ? "They appear automatically when you start one." : "Try a project, app, port, or branch.")
                        )
                        .frame(height: 230)
                    } else {
                        ForEach(filteredProjects) { project in
                            projectSection(project)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 8)
                        }

                        Spacer(minLength: 2)
                        if !filteredOtherWebServices.isEmpty {
                            secondarySection(
                                "Other Web endpoints",
                                services: filteredOtherWebServices,
                                isOpen: isSearching || expandedOtherWeb,
                                onToggle: { expandedOtherWeb.toggle() }
                            )
                        }
                        if !filteredOtherListenerServices.isEmpty {
                            secondarySection(
                                "Other listeners",
                                services: filteredOtherListenerServices,
                                isOpen: isSearching || expandedOtherListeners,
                                onToggle: { expandedOtherListeners.toggle() }
                            )
                        }
                    }
                }
                .frame(width: inventoryPanelWidth, alignment: .leading)
                .padding(.top, 5)
                .background(TransientScrollViewConfigurator(metrics: $scrollIndicator))
            }
            .scrollIndicators(.hidden)
            .contentMargins(.trailing, 0, for: .scrollContent)
            .overlay(alignment: .topTrailing) {
                TransientScrollIndicator(metrics: scrollIndicator)
            }

            Divider()
            HStack {
                Text(updatedText)
                Spacer()
                Text("⌘K Search")
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .frame(height: 25)
            .background(PortToolsTheme.chromeSurface(colorScheme))
        }
        .frame(width: inventoryPanelWidth, height: inventoryPanelHeight)
        .background(PortToolsTheme.panelBase(colorScheme))
        .overlay(alignment: .bottom) {
            if let message {
                Label(message, systemImage: "checkmark")
                    .font(.caption)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(Color(nsColor: .labelColor).opacity(0.9), in: RoundedRectangle(cornerRadius: 9))
                    .padding(.bottom, 38)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if let service = evidenceService {
                ZStack {
                    PortToolsTheme.panelBase(colorScheme)
                    ServiceDetailView(
                        service: service,
                        onBack: { hideServiceDetails() },
                        onReviewStop: { reviewStop(service) }
                    )
                }
                .id(service.id)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .offset(x: 14).combined(with: .opacity),
                            removal: .offset(x: 8).combined(with: .opacity)
                        )
                )
                .zIndex(2)
            }
        }
        .sheet(item: $renameTarget) { target in
            RenameView(target: target) { value in
                switch target.kind {
                case .project:
                    projectNames[target.key] = value
                    UserDefaults.standard.set(projectNames, forKey: "projectDisplayNames")
                case .service:
                    if let service = allServices.first(where: { serviceRenameKey($0) == target.key }) {
                        updatePreferences(service, ["displayName": value], message: "Name saved")
                    } else {
                        serviceNames[target.key] = value
                        UserDefaults.standard.set(serviceNames, forKey: "serviceDisplayNames")
                    }
                }
                if target.kind == .project { showMessage("Name saved") }
            }
        }
        .sheet(item: $stopReview) { review in
            StopConfirmationView(
                review: review,
                isStopping: $stopInProgress,
                onConfirm: { performStop(review) }
            )
        }
        .sheet(item: $forceStopReview) { review in
            ForceStopConfirmationView(
                review: review,
                isStopping: $stopInProgress,
                onConfirm: { performForceStop(review) }
            )
        }
        .task {
            if store.document == nil { store.refresh() }
        }
        .onReceive(timer) { _ in store.refresh(silent: true) }
        .preferredColorScheme(preferredColorScheme)
        .onKeyPress("k", phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            searchVisible = true
            searchFocused = true
            return .handled
        }
    }

    private var updatedText: String {
        guard let value = store.document?.generatedAt,
              let date = ISO8601DateFormatter().date(from: value) else { return "Local only" }
        return "Updated " + date.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder
    private func projectSection(_ project: ProjectGroup) -> some View {
        let pageServices = project.services.filter(isOpenablePage)
        let relatedServices = project.services.filter { !isOpenablePage($0) }
        let pageApplications = project.applications.filter { $0.services.contains(where: isOpenablePage) }
        let relatedIsOpen = isSearching || expandedRelated.contains(project.id)
        let inferredProjectName = project.name + (worktreeLabel(project.project).map { " · \($0)" } ?? "")
        let displayedProjectName = projectNames[project.id] ?? inferredProjectName
        let isSinglePage = pageServices.count == 1
        let projectIsExpanded = isSearching || !collapsedProjects.contains(project.id)

        VStack(spacing: 0) {
            if isSinglePage, let service = pageServices.first {
                mainServiceRow(
                    service,
                    projectContext: project.project == nil ? nil : compactProjectContext(project: project),
                    repositoryURL: repositoryWebURL(project.project),
                    fillsProjectCard: true,
                    backgroundServiceCount: relatedServices.count,
                    backgroundServicesExpanded: relatedIsOpen,
                    onToggleBackgroundServices: {
                        if relatedIsOpen { expandedRelated.remove(project.id) } else { expandedRelated.insert(project.id) }
                    },
                    onRenameProject: project.project == nil ? nil : {
                        beginProjectRename(project, displayedProjectName: displayedProjectName)
                    }
                )
            } else {
                projectHeader(
                    project,
                    displayedProjectName: displayedProjectName,
                    pageCount: pageServices.count,
                    applicationCount: pageApplications.count,
                    isExpanded: projectIsExpanded,
                    onToggle: {
                        if collapsedProjects.contains(project.id) {
                            collapsedProjects.remove(project.id)
                        } else {
                            collapsedProjects.insert(project.id)
                        }
                    }
                )

                ExpandableContent(isExpanded: projectIsExpanded) {
                    VStack(spacing: 0) {
                        ForEach(project.applications) { application in
                            let applicationPages = application.services.filter(isOpenablePage)
                            if !applicationPages.isEmpty && pageApplications.count > 1 {
                                HStack(spacing: 6) {
                                    Text(application.name).font(.system(size: 10, weight: .semibold))
                                    Text(application.application.map { "\($0.manifest) · \($0.relativePath)" } ?? "command path")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.leading, 46)
                                .padding(.trailing, 10)
                                .padding(.top, 5)
                            }
                            if !applicationPages.isEmpty {
                                VStack(spacing: 2) {
                                    ForEach(applicationPages) { service in
                                        mainServiceRow(
                                            service,
                                            projectContext: nil,
                                            repositoryURL: nil,
                                            fillsProjectCard: false,
                                            backgroundServiceCount: 0,
                                            backgroundServicesExpanded: false,
                                            onToggleBackgroundServices: nil,
                                            onRenameProject: nil
                                        )
                                    }
                                }
                                .padding(.leading, 36)
                                .padding(.trailing, 10)
                            }
                        }
                        if !relatedServices.isEmpty {
                            DisclosureRow(
                                isExpanded: relatedIsOpen,
                                level: 1,
                                contentInsets: EdgeInsets(top: 3, leading: 38, bottom: 3, trailing: 10),
                                minimumHeight: 26
                            ) {
                                if relatedIsOpen { expandedRelated.remove(project.id) } else { expandedRelated.insert(project.id) }
                            } content: {
                                Text("\(relatedServices.count) supporting service\(relatedServices.count == 1 ? "" : "s")")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            ExpandableContent(isExpanded: relatedIsOpen) {
                                VStack(spacing: 2) {
                                    ForEach(relatedServices) { service in
                                        RelatedServiceRow(service: service, parentName: displayedProjectName) {
                                            showServiceDetails(service)
                                        }
                                    }
                                }
                                .padding(.leading, 48)
                                .padding(.trailing, 10)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }

            if isSinglePage && relatedIsOpen && !relatedServices.isEmpty {
                VStack(spacing: 2) {
                    ForEach(relatedServices) { service in
                        RelatedServiceRow(
                            service: service,
                            parentName: displayedProjectName
                        ) { showServiceDetails(service) }
                    }
                }
                .padding(.leading, isSinglePage ? 28 : 48)
                .padding(.trailing, 10)
                .transition(disclosureContentTransition)
            }
        }
        .padding(.bottom, isSinglePage ? 0 : 2)
        .background(PortToolsTheme.groupSurface(colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PortToolsTheme.groupBorder(colorScheme), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.11 : 0.035), radius: 7, y: 2)
    }

    private func beginProjectRename(_ project: ProjectGroup, displayedProjectName: String) {
        renameTarget = RenameTarget(
            key: project.id,
            kind: .project,
            currentName: projectNames[project.id] ?? displayedProjectName
        )
    }

    private func compactProjectContext(project: ProjectGroup) -> String {
        var parts: [String] = []
        parts.append(project.project?.branch ?? (project.project?.isWorktree == true ? "Codex worktree" : "No Git branch"))
        if let remote = compactRepositoryLabel(project.project?.remoteUrl) { parts.append(remote) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func projectHeader(
        _ project: ProjectGroup,
        displayedProjectName: String,
        pageCount: Int,
        applicationCount: Int,
        isExpanded: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        let countText = applicationCount > 1
            ? "\(applicationCount) apps"
            : "\(pageCount) pages"
        DisclosureRow(
            isExpanded: isExpanded,
            level: 0,
            contentInsets: EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8),
            minimumHeight: 50,
            trailingChevron: true,
            action: onToggle
        ) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    if pinnedProjects.contains(project.id) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    HoverFullTitleText(
                        title: displayedProjectName,
                        font: .system(size: 13, weight: .semibold),
                        nsFont: .systemFont(ofSize: 13, weight: .semibold)
                    )
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green.opacity(0.72))
                        .help("All visible Web pages responded successfully")
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(
                        [
                            project.project?.branch ?? (project.project?.isWorktree == true ? "Codex worktree" : "No Git branch"),
                            compactRepositoryLabel(project.project?.remoteUrl)
                        ]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            }
            .layoutPriority(1)
            Spacer(minLength: 5)
            Text(countText)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1), in: Capsule())
        }
        .contextMenu {
            if let repositoryURL = repositoryWebURL(project.project) {
                Button("Open repository", systemImage: "arrow.up.right") {
                    NSWorkspace.shared.open(repositoryURL)
                }
            }
            Button("Rename project…", systemImage: "pencil") {
                beginProjectRename(project, displayedProjectName: displayedProjectName)
            }
            Button(
                pinnedProjects.contains(project.id) ? "Unpin" : "Pin",
                systemImage: pinnedProjects.contains(project.id) ? "pin.slash" : "pin"
            ) {
                if pinnedProjects.contains(project.id) {
                    pinnedProjects.remove(project.id)
                } else {
                    pinnedProjects.insert(project.id)
                }
                UserDefaults.standard.set(Array(pinnedProjects).sorted(), forKey: "pinnedProjectIDs")
            }
        }
    }

    private func mainServiceRow(
        _ service: ServiceRecord,
        projectContext: String?,
        repositoryURL: URL?,
        fillsProjectCard: Bool = false,
        backgroundServiceCount: Int,
        backgroundServicesExpanded: Bool,
        onToggleBackgroundServices: (() -> Void)?,
        onRenameProject: (() -> Void)?
    ) -> some View {
        ServiceRow(
            service: service,
            displayName: serviceNames[serviceRenameKey(service)] ?? serviceName(service),
            projectContext: projectContext,
            repositoryURL: repositoryURL,
            backgroundServiceCount: backgroundServiceCount,
            backgroundServicesExpanded: backgroundServicesExpanded,
            fillsProjectCard: fillsProjectCard,
            onToggleBackgroundServices: onToggleBackgroundServices,
            onRename: {
                renameTarget = RenameTarget(
                    key: serviceRenameKey(service),
                    kind: .service,
                    currentName: serviceNames[serviceRenameKey(service)] ?? serviceName(service)
                )
            },
            onRenameProject: onRenameProject,
            onSaveAlias: { alias in
                store.assignAlias(alias, to: service) { result in
                    switch result {
                    case .success(let route): showMessage("Local address ready · \(route.alias).localhost")
                    case .failure(let error): showMessage(error.localizedDescription)
                    }
                }
            },
            onRemoveAlias: service.route == nil ? nil : {
                guard let alias = service.route?.alias else { return }
                store.removeAlias(alias) { result in
                    switch result {
                    case .success: showMessage("Local address removed")
                    case .failure(let error): showMessage(error.localizedDescription)
                    }
                }
            },
            onEvidence: { showServiceDetails(service) },
            onReviewStop: { reviewStop(service) },
            onTogglePin: { updatePreferences(service, ["pinned": !service.preferences.pinned], message: service.preferences.pinned ? "Unpinned" : "Pinned") },
            onIgnore: { updatePreferences(service, ["ignored": true], message: "Moved to Ignored") },
            onClassification: { value in updatePreferences(service, ["classificationOverride": value], message: "Display role updated") },
            onMessage: showMessage
        )
    }

    @ViewBuilder
    private func secondarySection(
        _ label: String,
        services: [ServiceRecord],
        isOpen: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 2) {
            DisclosureRow(
                isExpanded: isOpen,
                isEnabled: !isSearching,
                animatesContent: false,
                level: 1,
                contentInsets: EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 8),
                minimumHeight: 30,
                contentSpacing: 0
            ) {
                onToggle()
            } content: {
                Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                Spacer()
                Text(String(services.count))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }

            ExpandableContent(isExpanded: isOpen) {
                VStack(spacing: 2) {
                    ForEach(services) { service in
                        SecondaryServiceRow(service: service) {
                            showServiceDetails(service)
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.bottom, 5)
            }
        }
        .padding(.leading, 8)
        .padding(.vertical, 1)
    }

    private func showServiceDetails(_ service: ServiceRecord) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.1) : detailNavigationAnimation) {
            evidenceService = service
        }
    }

    private func hideServiceDetails() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.1) : detailNavigationAnimation) {
            evidenceService = nil
        }
    }

    private func reviewStop(_ service: ServiceRecord) {
        store.stopPlan(for: service) { result in
            switch result {
            case .success(let plan):
                stopReview = StopReview(service: service, plan: plan)
            case .failure(let error):
                showMessage(error.localizedDescription)
            }
        }
    }

    private func performStop(_ review: StopReview) {
        guard let planToken = review.plan.planToken else { return }
        stopInProgress = true
        store.gracefulStop(review.service, planToken: planToken) { result in
            stopInProgress = false
            stopReview = nil
            switch result {
            case .success(let stopResult) where stopResult.success:
                evidenceService = nil
                showMessage("Service stopped and listener released")
            case .success(let stopResult):
                if stopResult.forceStopAvailable, let token = stopResult.gracefulAttemptToken {
                    store.forceStopPlan(review.service, gracefulAttemptToken: token) { forceResult in
                        switch forceResult {
                        case .success(let plan): self.forceStopReview = ForceStopReview(service: review.service, plan: plan)
                        case .failure(let error): self.showMessage(error.localizedDescription)
                        }
                    }
                } else {
                    showMessage(stopResult.reasons.first ?? "Service could not be stopped safely")
                }
            case .failure(let error):
                showMessage(error.localizedDescription)
            }
        }
    }

    private func performForceStop(_ review: ForceStopReview) {
        guard let token = review.plan.planToken else { return }
        stopInProgress = true
        store.forceStop(review.service, planToken: token) { result in
            stopInProgress = false
            forceStopReview = nil
            switch result {
            case .success(let value) where value.success:
                evidenceService = nil
                showMessage("Service force-stopped and listener released")
            case .success(let value): showMessage(value.reasons.first ?? "Force stop could not complete")
            case .failure(let error): showMessage(error.localizedDescription)
            }
        }
    }

    private func updatePreferences(_ service: ServiceRecord, _ patch: [String: Any], message: String) {
        store.updatePreferences(service, patch: patch) { result in
            switch result {
            case .success: showMessage(message)
            case .failure(let error): showMessage(error.localizedDescription)
            }
        }
    }

    private func showMessage(_ value: String) {
        withAnimation { message = value }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { if message == value { message = nil } }
        }
    }
}
