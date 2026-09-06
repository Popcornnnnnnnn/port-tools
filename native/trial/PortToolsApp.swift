import AppKit
import Combine
import Foundation
import SwiftUI

struct ListenerRecord: Codable, Sendable {
    let address: String
    let port: Int
    let bindScope: String
}

struct ProcessRecord: Codable, Sendable {
    let pid: Int
    let name: String?
    let command: String?
    let cwd: String?
    let started: String?
}

struct ProjectRecord: Codable, Sendable {
    let root: String
    let name: String
    let repositoryName: String?
    let worktreeName: String?
    let branch: String?
    let remoteUrl: String?
    let isWorktree: Bool?
}

struct ApplicationRecord: Codable, Sendable {
    let root: String
    let relativePath: String
    let name: String
    let manifest: String
}

struct HTTPRecord: Codable, Sendable {
    let status: Int?
    let title: String?
}

struct EvidenceRecord: Codable, Identifiable, Sendable {
    let kind: String
    var id: String { kind }
}

struct ObservationRecord: Codable, Sendable {
    let classification: String
    let `protocol`: String
    let role: String?
    let framework: String?
    let http: HTTPRecord?
    let evidence: [EvidenceRecord]
}

struct RelevanceRecord: Codable, Sendable {
    let developerRelevant: Bool
}

struct RouteRecord: Codable, Sendable {
    let alias: String
    let port: Int
    let scheme: String
    let hostMode: String
    let tlsPolicy: String
    let projectRoot: String?
    let applicationRoot: String?
    let url: String
}

struct ServiceRecord: Codable, Identifiable, Sendable {
    let id: String
    let listener: ListenerRecord
    let process: ProcessRecord
    let project: ProjectRecord?
    let application: ApplicationRecord?
    let observation: ObservationRecord
    let relevance: RelevanceRecord
    let route: RouteRecord?
}

struct ScanDocument: Codable, Sendable {
    let generatedAt: String
    let services: [ServiceRecord]
}

struct ApplicationGroup: Identifiable {
    let id: String
    let name: String
    let application: ApplicationRecord?
    var services: [ServiceRecord]
}

struct ProjectGroup: Identifiable {
    let id: String
    let name: String
    let project: ProjectRecord?
    var applications: [ApplicationGroup]

    var services: [ServiceRecord] {
        applications.flatMap(\.services)
    }
}

enum CoreError: LocalizedError {
    case missingResource
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "Bundled Port Tools core is missing."
        case .failed(let message):
            return message
        }
    }
}

protocol InventoryProviding: Sendable {
    func scan() throws -> ScanDocument
    func assignAlias(_ alias: String, to service: ServiceRecord) throws -> RouteRecord
    func removeAlias(_ alias: String) throws
}

final class CoreRuntime: @unchecked Sendable {
    static let shared = CoreRuntime()

    private let lock = NSLock()
    private var process: Process?
    private var logHandle: FileHandle?

    private var executableURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/port-tools-core")
    }

    private var stateRoot: URL {
        if let override = ProcessInfo.processInfo.environment["PORT_TOOLS_STATE_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Port Tools", isDirectory: true)
    }

    private var socketURL: URL { stateRoot.appendingPathComponent("runtime/core.sock") }
    private var routeStateURL: URL { stateRoot.appendingPathComponent("routes.json") }
    private var logURL: URL {
        if ProcessInfo.processInfo.environment["PORT_TOOLS_STATE_ROOT"] != nil {
            return stateRoot.appendingPathComponent("core.log")
        }
        return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Port Tools/core.log")
    }

    private init() {}

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        var lastError: Error = CoreError.failed("Port Tools core could not start.")
        for attempt in 0..<8 {
            do {
                try startLocked()
                return
            } catch CoreError.missingResource {
                throw CoreError.missingResource
            } catch {
                lastError = error
                if attempt < 7 { Thread.sleep(forTimeInterval: 0.35) }
            }
        }
        throw lastError
    }

    private func startLocked() throws {
        if let process, process.isRunning, FileManager.default.fileExists(atPath: socketURL.path) { return }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CoreError.missingResource
        }
        try FileManager.default.createDirectory(at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: routeStateURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()

        let task = Process()
        task.executableURL = executableURL
        task.arguments = [
            "serve",
            "--socket", socketURL.path,
            "--state", routeStateURL.path,
            "--proxy", ProcessInfo.processInfo.environment["PORT_TOOLS_PROXY_ADDRESS"] ?? "127.0.0.1:17890",
            "--parent-pid", String(ProcessInfo.processInfo.processIdentifier),
        ]
        task.standardOutput = logHandle
        task.standardError = logHandle
        try task.run()
        process = task
        self.logHandle = logHandle

        for _ in 0..<80 {
            if !task.isRunning {
                process = nil
                try? logHandle.close()
                self.logHandle = nil
                throw CoreError.failed("Port Tools core exited during startup. See \(logURL.path).")
            }
            if FileManager.default.fileExists(atPath: socketURL.path) { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        task.terminate()
        process = nil
        try? logHandle.close()
        self.logHandle = nil
        throw CoreError.failed("Port Tools core did not become ready.")
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        if let process, process.isRunning { process.terminate() }
        process = nil
        try? logHandle?.close()
        logHandle = nil
    }

    func request(method: String = "GET", path: String, body: Data? = nil) throws -> Data {
        try start()
        let task = Process()
        let output = Pipe()
        let errors = Pipe()
        task.executableURL = executableURL
        var arguments = ["request", "--socket", socketURL.path, "--method", method, "--path", path]
        if let body, let value = String(data: body, encoding: .utf8) {
            arguments += ["--body", value]
        }
        task.arguments = arguments
        task.standardOutput = output
        task.standardError = errors
        try task.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let apiMessage = (try? JSONSerialization.jsonObject(with: data))
                .flatMap { $0 as? [String: Any] }?["error"] as? String
            let stderr = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CoreError.failed(apiMessage ?? stderr ?? "Port Tools core request failed.")
        }
        return data
    }
}

struct BundledGoInventoryProvider: InventoryProviding {
    func scan() throws -> ScanDocument {
        let data = try CoreRuntime.shared.request(path: "/v1/services")
        return try JSONDecoder().decode(ScanDocument.self, from: data)
    }

    func assignAlias(_ alias: String, to service: ServiceRecord) throws -> RouteRecord {
        let body: [String: Any] = [
            "port": service.listener.port,
            "scheme": service.observation.protocol == "https" ? "https" : "http",
            "hostMode": "rewrite",
            "tlsPolicy": "verify",
            "projectRoot": service.project?.root ?? "",
            "applicationRoot": service.application?.root ?? "",
            "previousAlias": service.route?.alias ?? "",
        ]
        let requestBody = try JSONSerialization.data(withJSONObject: body)
        let encodedAlias = alias.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? alias
        let data = try CoreRuntime.shared.request(method: "PUT", path: "/v1/routes/\(encodedAlias)", body: requestBody)
        return try JSONDecoder().decode(RouteRecord.self, from: data)
    }

    func removeAlias(_ alias: String) throws {
        let encodedAlias = alias.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? alias
        _ = try CoreRuntime.shared.request(method: "DELETE", path: "/v1/routes/\(encodedAlias)")
    }
}

@MainActor
final class InventoryStore: ObservableObject {
    @Published private(set) var document: ScanDocument?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let provider: InventoryProviding = BundledGoInventoryProvider()

    func refresh(silent: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true
        let provider = provider
        DispatchQueue.global(qos: silent ? .utility : .userInitiated).async {
            let result = Result { try provider.scan() }
            DispatchQueue.main.async {
                switch result {
                case .success(let document):
                    self.document = document
                    self.errorMessage = nil
                    NSLog("Port Tools scan loaded %d listeners", document.services.count)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    NSLog("Port Tools scan failed: %@", error.localizedDescription)
                }
                self.isRefreshing = false
            }
        }
    }

    func assignAlias(_ alias: String, to service: ServiceRecord, completion: @escaping (Result<RouteRecord, Error>) -> Void) {
        let provider = provider
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try provider.assignAlias(alias, to: service) }
            DispatchQueue.main.async {
                completion(result)
                if case .success = result { self.refresh() }
            }
        }
    }

    func removeAlias(_ alias: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let provider = provider
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try provider.removeAlias(alias) }
            DispatchQueue.main.async {
                completion(result)
                if case .success = result { self.refresh() }
            }
        }
    }
}

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
    if let title = service.observation.http?.title, !title.isEmpty { return title }
    if let name = service.application?.name, !name.isEmpty { return name }
    if let framework = service.observation.framework, !framework.isEmpty { return framework }
    if let commandName = commandApplicationName(service), !commandName.isEmpty { return commandName }
    return service.process.name ?? "Web service :\(service.listener.port)"
}

func isOpenablePage(_ service: ServiceRecord) -> Bool {
    if let role = service.observation.role { return role == "page" }
    guard let status = service.observation.http?.status else {
        return service.observation.classification == "suspected-web"
    }
    return (200..<400).contains(status)
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

struct ServiceDetailView: View {
    let service: ServiceRecord
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
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
                }
                .padding(18)
                .background(OverlayScrollViewConfigurator())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

enum RenameKind {
    case project
    case service
}

struct RenameTarget: Identifiable {
    let id = UUID()
    let key: String
    let kind: RenameKind
    let currentName: String
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

private let disclosureAnimation = Animation.easeOut(duration: 0.15)
private let disclosureContentTransition = AnyTransition.asymmetric(
    insertion: .offset(y: -4).combined(with: .opacity),
    removal: .opacity
)

struct DisclosureRow<Content: View>: View {
    let isExpanded: Bool
    let isEnabled: Bool
    let level: Int
    let contentInsets: EdgeInsets
    let minimumHeight: CGFloat
    let contentSpacing: CGFloat?
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    init(
        isExpanded: Bool,
        isEnabled: Bool = true,
        level: Int = 0,
        contentInsets: EdgeInsets,
        minimumHeight: CGFloat = 0,
        contentSpacing: CGFloat? = nil,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isExpanded = isExpanded
        self.isEnabled = isEnabled
        self.level = level
        self.contentInsets = contentInsets
        self.minimumHeight = minimumHeight
        self.contentSpacing = contentSpacing
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

    var body: some View {
        Button {
            guard isEnabled else { return }
            withAnimation(disclosureAnimation) { action() }
        } label: {
            HStack(spacing: contentSpacing ?? (level == 0 ? 7 : 8)) {
                Image(systemName: "chevron.right")
                    .font(.system(size: level == 0 ? 8.5 : 8, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(Color.secondary.opacity(chevronOpacity))
                    .frame(width: level == 0 ? 14 : 12)
                content()
            }
            .contentShape(Rectangle())
            .padding(contentInsets)
            .frame(minHeight: minimumHeight)
            .background(
                Color.secondary.opacity(isHovered && isEnabled ? hoverOpacity : 0),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
        }
        .animation(disclosureAnimation, value: isExpanded)
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

/// Keeps SwiftUI's scroll view from reserving a persistent gutter. The native
/// overlay scroller fades away when idle and appears above content while the
/// user scrolls, matching standard macOS menu-bar-panel behavior.
struct OverlayScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configure(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSView, attemptsRemaining: Int = 8) {
        DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else {
                guard attemptsRemaining > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    configure(view, attemptsRemaining: attemptsRemaining - 1)
                }
                return
            }

            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = true
            scrollView.verticalScroller?.controlSize = .small
            scrollView.scrollerKnobStyle = .default
            scrollView.tile()
        }
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
                        Text(title)
                            .lineLimit(1)
                            .underline(isHovered)
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
                Text(title)
                    .lineLimit(1)
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

struct ServiceRow: View {
    let service: ServiceRecord
    let displayName: String
    let projectContext: String?
    let repositoryURL: URL?
    let backgroundServiceCount: Int
    let backgroundServicesExpanded: Bool
    let onToggleBackgroundServices: (() -> Void)?
    let onRename: () -> Void
    let onRenameProject: (() -> Void)?
    let onSaveAlias: (String) -> Void
    let onRemoveAlias: (() -> Void)?
    let onEvidence: () -> Void
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
                if backgroundServiceCount > 0, let onToggleBackgroundServices {
                    BackgroundServiceButton(
                        count: backgroundServiceCount,
                        isExpanded: backgroundServicesExpanded,
                        action: onToggleBackgroundServices
                    )
                }
                Spacer(minLength: 4)
                if let age = relativeAge(service.process.started) {
                    Text(age)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .help("Process has been running for \(age)")
                }

                Menu {
                    Button("Copy address", systemImage: "doc.on.doc") { copyAddress() }
                    Button("Rename display name…", systemImage: "pencil", action: onRename)
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
                        Text(".localhost:17890")
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Color.secondary.opacity(isHovered ? 0.04 : 0),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
        }
        .onDisappear { removeAliasClickMonitor() }
    }

    private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(primaryServiceURL(service)?.absoluteString ?? "", forType: .string)
        onMessage("Address copied")
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
                        Text(age)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .help("Process has been running for \(age)")
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
            Color.secondary.opacity(isHovered ? 0.035 : 0),
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
                    Text(age)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .help("Process has been running for \(age)")
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
            Color.secondary.opacity(isHovered ? 0.035 : 0),
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
    @State private var expandedRelated = Set<String>()
    @State private var expandedOtherWeb = false
    @State private var expandedOtherListeners = false
    @State private var evidenceService: ServiceRecord?
    @State private var renameTarget: RenameTarget?
    @State private var projectNames = UserDefaults.standard.dictionary(forKey: "projectDisplayNames") as? [String: String] ?? [:]
    @State private var serviceNames = UserDefaults.standard.dictionary(forKey: "serviceDisplayNames") as? [String: String] ?? [:]
    @State private var query = ""
    @State private var searchVisible = false
    @State private var message: String?
    @FocusState private var searchFocused: Bool

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var allServices: [ServiceRecord] { store.document?.services ?? [] }
    private var webServices: [ServiceRecord] {
        allServices.filter { webClassifications.contains($0.observation.classification) }
    }
    private var developmentServices: [ServiceRecord] {
        webServices.filter(\.relevance.developerRelevant)
    }
    private var developmentPages: [ServiceRecord] {
        developmentServices.filter(isOpenablePage)
    }
    private var projects: [ProjectGroup] {
        groupServices(developmentServices).filter { $0.services.contains(where: isOpenablePage) }
    }
    private var displayedProjectServiceIDs: Set<String> {
        Set(projects.flatMap(\.services).map(\.id))
    }
    private var otherWebServices: [ServiceRecord] {
        webServices.filter { !displayedProjectServiceIDs.contains($0.id) }
    }
    private var otherListenerServices: [ServiceRecord] {
        allServices.filter { !webClassifications.contains($0.observation.classification) }
    }
    private var searchNeedle: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var isSearching: Bool { !searchNeedle.isEmpty }
    private var inventorySummary: String {
        let projectLabel = projects.count == 1 ? "project" : "projects"
        let appLabel = developmentPages.count == 1 ? "Web app" : "Web apps"
        return "\(projects.count) \(projectLabel) · \(developmentPages.count) \(appLabel)"
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
                        Text("Port Tools").font(.title3.weight(.bold))
                        HStack(spacing: 5) {
                            Circle().fill(Color.green).frame(width: 5, height: 5)
                            Text("LIVE")
                        }
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
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
                    Button("Quit Port Tools") { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "ellipsis") }
                .menuIndicator(.hidden)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

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
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.6)))
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
                .background(OverlayScrollViewConfigurator())
            }

            Divider()
            HStack {
                Text(updatedText)
                Spacer()
                Text("⌘K Search")
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .frame(height: 25)
        }
        .frame(width: 410, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
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
                    Color(nsColor: .windowBackgroundColor)
                    ServiceDetailView(service: service) {
                        evidenceService = nil
                    }
                }
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
                    serviceNames[target.key] = value
                    UserDefaults.standard.set(serviceNames, forKey: "serviceDisplayNames")
                }
                showMessage("Name saved")
            }
        }
        .task {
            if store.document == nil { store.refresh() }
        }
        .onReceive(timer) { _ in store.refresh(silent: true) }
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

        VStack(spacing: 0) {
            if isSinglePage, let service = pageServices.first {
                mainServiceRow(
                    service,
                    projectContext: compactProjectContext(project: project),
                    repositoryURL: repositoryWebURL(project.project),
                    backgroundServiceCount: relatedServices.count,
                    backgroundServicesExpanded: relatedIsOpen,
                    onToggleBackgroundServices: {
                        if relatedIsOpen { expandedRelated.remove(project.id) } else { expandedRelated.insert(project.id) }
                    },
                    onRenameProject: { beginProjectRename(project, displayedProjectName: displayedProjectName) }
                )
                .padding(.horizontal, 10)
                .padding(.top, 2)
            } else {
                projectHeader(
                    project,
                    displayedProjectName: displayedProjectName,
                    pageCount: pageServices.count,
                    applicationCount: pageApplications.count,
                    backgroundServiceCount: relatedServices.count,
                    backgroundServicesExpanded: relatedIsOpen,
                    onToggleBackgroundServices: {
                        if relatedIsOpen { expandedRelated.remove(project.id) } else { expandedRelated.insert(project.id) }
                    }
                )

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
                }
                .padding(.top, 2)
            }

            if relatedIsOpen && !relatedServices.isEmpty {
                VStack(spacing: 2) {
                    ForEach(relatedServices) { service in
                        RelatedServiceRow(
                            service: service,
                            parentName: displayedProjectName
                        ) { evidenceService = service }
                    }
                }
                .padding(.leading, isSinglePage ? 28 : 48)
                .padding(.trailing, 10)
                .transition(disclosureContentTransition)
            }
        }
        .padding(.bottom, 2)
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
        backgroundServiceCount: Int,
        backgroundServicesExpanded: Bool,
        onToggleBackgroundServices: @escaping () -> Void
    ) -> some View {
        let countText = applicationCount > 1
            ? "\(applicationCount) apps"
            : "\(pageCount) pages"
        HStack(spacing: 7) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    ProjectTitleLink(title: displayedProjectName, destination: repositoryWebURL(project.project))
                    if backgroundServiceCount > 0 {
                        BackgroundServiceButton(
                            count: backgroundServiceCount,
                            isExpanded: backgroundServicesExpanded,
                            action: onToggleBackgroundServices
                        )
                    }
                }
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(project.project?.branch ?? (project.project?.isWorktree == true ? "Codex worktree" : "No Git branch"))
                    if let remote = compactRepositoryLabel(project.project?.remoteUrl) {
                        Text("·")
                        Text(remote).lineLimit(1)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            Text(countText)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contextMenu {
            Button("Rename project…", systemImage: "pencil") {
                beginProjectRename(project, displayedProjectName: displayedProjectName)
            }
        }
    }

    private func mainServiceRow(
        _ service: ServiceRecord,
        projectContext: String?,
        repositoryURL: URL?,
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
            onEvidence: { evidenceService = service },
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
                level: 1,
                contentInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12),
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

            if isOpen {
                VStack(spacing: 2) {
                    ForEach(services) { service in
                        SecondaryServiceRow(service: service) {
                            evidenceService = service
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.trailing, 8)
                .padding(.bottom, 5)
                .transition(disclosureContentTransition)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }

    private func showMessage(_ value: String) {
        withAnimation { message = value }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { if message == value { message = nil } }
        }
    }
}

final class PortToolsAppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindow: NSWindow?
    private var previewStore: InventoryStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.contains("--preview-window") else { return }
        let store = InventoryStore()
        store.refresh()
        let host = NSHostingView(rootView: InventoryView(store: store))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 640),
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

    func applicationWillTerminate(_ notification: Notification) {
        CoreRuntime.shared.stop()
    }
}

@main
struct PortToolsApp: App {
    @NSApplicationDelegateAdaptor(PortToolsAppDelegate.self) private var appDelegate
    @StateObject private var store = InventoryStore()

    init() {
        try? CoreRuntime.shared.start()
        let initialStore = InventoryStore()
        _store = StateObject(wrappedValue: initialStore)
        initialStore.refresh()
    }

    var body: some Scene {
        MenuBarExtra("Port Tools", systemImage: "network") {
            InventoryView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
