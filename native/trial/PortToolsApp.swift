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

struct StatusPill: View {
    let service: ServiceRecord

    var body: some View {
        let exposed = service.listener.bindScope != "loopback"
        let suspected = service.observation.classification == "suspected-web"
        Label(
            exposed ? "LAN exposed" : suspected ? "Likely Web" : "Web verified",
            systemImage: exposed ? "network" : suspected ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
        )
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(exposed || suspected ? Color.orange : Color.green)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background((exposed || suspected ? Color.orange : Color.green).opacity(0.1), in: Capsule())
        .help(exposed
            ? "Listening beyond 127.0.0.1. Other devices on this LAN may be able to connect."
            : suspected
                ? "The endpoint looks like Web traffic, but verification is incomplete."
                : "A local HTTP or HTTPS response was verified."
        )
    }
}

struct EvidenceView: View {
    let service: ServiceRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: isOpenablePage(service) ? "checkmark.shield.fill" : "point.3.connected.trianglepath.dotted")
                    .font(.title2)
                    .foregroundStyle(isOpenablePage(service) ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isOpenablePage(service) ? "Why this is a Web app" : "Why this service was detected").font(.headline)
                    Text("\(isOpenablePage(service) ? serviceName(service) : relatedServiceName(service)) · port \(service.listener.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(service.observation.evidence.enumerated()), id: \.offset) { _, evidence in
                    Label(evidence.kind.replacingOccurrences(of: "-", with: " "), systemImage: "checkmark")
                        .font(.caption)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow { Text("Project").foregroundStyle(.secondary); Text(service.project?.name ?? "Unassigned") }
                GridRow { Text("Application").foregroundStyle(.secondary); Text(service.application?.name ?? commandApplicationName(service) ?? "Project root") }
                GridRow { Text("Process").foregroundStyle(.secondary); Text(service.process.command ?? "Unknown").lineLimit(3) }
                GridRow { Text("Role").foregroundStyle(.secondary); Text(isOpenablePage(service) ? "Openable Web page" : relatedServiceDescription(service)) }
                GridRow { Text(isOpenablePage(service) ? "Open address" : "Local endpoint").foregroundStyle(.secondary); Text(serviceURL(service)?.absoluteString ?? "Unknown") }
                GridRow { Text("Listening on").foregroundStyle(.secondary); Text(listenerEndpoint(service)) }
                GridRow { Text("Bind scope").foregroundStyle(.secondary); Text(service.listener.bindScope == "loopback" ? "This Mac only" : "Potentially reachable on this LAN") }
            }
            .font(.caption)
        }
        .padding(18)
        .frame(width: 410)
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

struct AliasTarget: Identifiable {
    let id = UUID()
    let service: ServiceRecord
}

struct AliasView: View {
    let target: AliasTarget
    let onSave: (String) -> Void
    let onRemove: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var alias: String

    init(target: AliasTarget, onSave: @escaping (String) -> Void, onRemove: ((String) -> Void)? = nil) {
        self.target = target
        self.onSave = onSave
        self.onRemove = onRemove
        _alias = State(initialValue: target.service.route?.alias ?? suggestedAlias(target.service))
    }

    private var normalizedAlias: String {
        alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var valid: Bool {
        normalizedAlias.range(of: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"#, options: .regularExpression) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(target.service.route == nil ? "Add local address" : "Local address")
                    .font(.headline)
                Text("A stable name for this app on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                TextField("project-name", text: $alias)
                    .textFieldStyle(.plain)
                    .onSubmit { save() }
                Text(".localhost:17890")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(valid ? Color.accentColor.opacity(0.55) : Color.red.opacity(0.75)))

            Text("Routes only on this Mac's IPv4/IPv6 loopback. No hosts file, certificate, sudo, or public tunnel is used.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                if let currentAlias = target.service.route?.alias, let onRemove {
                    Button("Remove", role: .destructive) {
                        onRemove(currentAlias)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!valid)
            }
        }
        .padding(18)
        .frame(width: 390)
    }

    private func save() {
        guard valid else { return }
        onSave(normalizedAlias)
        dismiss()
    }
}

struct ServiceRow: View {
    let service: ServiceRecord
    let displayName: String
    let selected: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onAlias: () -> Void
    let onEvidence: () -> Void
    let onMessage: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        StatusPill(service: service)
                        Spacer(minLength: 4)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: service.route == nil ? "terminal" : "link")
                        Text(compactServiceAddress(service))
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .foregroundStyle(service.route == nil ? Color.secondary : Color.accentColor)
                        if service.listener.bindScope != "loopback" {
                            Text("→")
                            Text("listens \(listenerEndpoint(service))")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let age = relativeAge(service.process.started) {
                            Text(age)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)

            if selected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Button("Open", systemImage: "arrow.up.forward.square") {
                            if let url = primaryServiceURL(service) { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Copy", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(primaryServiceURL(service)?.absoluteString ?? "", forType: .string)
                            onMessage("Address copied")
                        }
                        Button("Rename", systemImage: "pencil", action: onRename)
                        Spacer(minLength: 0)
                        Menu {
                            Button("Why this is Web", systemImage: "questionmark.circle", action: onEvidence)
                            Divider()
                            Button("Stop (preview only)", systemImage: "stop.circle") {
                                onMessage("Trial preview only · no process was stopped")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .controlSize(.small)

                    Button(action: onAlias) {
                        Label(
                            service.route?.url.replacingOccurrences(of: "http://", with: "") ?? "Add a stable .localhost address",
                            systemImage: service.route == nil ? "link.badge.plus" : "link"
                        )
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(service.route == nil ? Color.accentColor : Color.secondary)

                    if let path = service.project?.root {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(path, forType: .string)
                            onMessage("Project path copied")
                        } label: {
                            Label(compactPath(path), systemImage: "folder")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(selected ? Color.accentColor.opacity(0.06) : Color.clear)
    }
}

struct RelatedServiceRow: View {
    let service: ServiceRecord
    let onEvidence: () -> Void

    var body: some View {
        Button(action: onEvidence) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(relatedServiceName(service))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if service.listener.bindScope != "loopback" {
                        Label("LAN exposed", systemImage: "network")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.1), in: Capsule())
                    }
                    Spacer(minLength: 4)
                    if let age = relativeAge(service.process.started) {
                        Text(age).font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                    Text(relatedServiceDescription(service))
                    Text("·")
                    Text(compactRawServiceAddress(service))
                        .font(.system(size: 9, design: .monospaced))
                    if service.listener.bindScope != "loopback" {
                        Text("→")
                        Text("listens \(listenerEndpoint(service))")
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "info.circle")
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .help("Show detection evidence")
    }
}

struct InventoryView: View {
    @ObservedObject var store: InventoryStore
    @State private var expanded = Set<String>()
    @State private var expandedRelated = Set<String>()
    @State private var initializedExpansion = false
    @State private var selectedServiceID: String?
    @State private var evidenceService: ServiceRecord?
    @State private var renameTarget: RenameTarget?
    @State private var aliasTarget: AliasTarget?
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
    private var otherWebCount: Int {
        webServices.filter { !displayedProjectServiceIDs.contains($0.id) }.count
    }
    private var otherListenerCount: Int { allServices.count - webServices.count }

    private var filteredProjects: [ProjectGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
                        Label("LIVE", systemImage: "circle.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.green)
                    }
                    Text(store.document == nil ? "Scanning local Web apps…" : "\(projects.count) projects · \(developmentPages.count) Web apps")
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
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

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
                    } else if filteredProjects.isEmpty {
                        ContentUnavailableView(
                            query.isEmpty ? "No development Web apps" : "No matching Web apps",
                            systemImage: "magnifyingglass",
                            description: Text(query.isEmpty ? "They appear automatically when you start one." : "Try a project, app, port, or branch.")
                        )
                        .frame(height: 230)
                    } else {
                        ForEach(filteredProjects) { project in
                            projectSection(project)
                            Divider().padding(.leading, 14)
                        }

                        if query.isEmpty {
                            quietCountRow("Other Web endpoints", count: otherWebCount)
                            Divider().padding(.leading, 30)
                            quietCountRow("Other listeners", count: otherListenerCount)
                        }
                    }
                }
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
            .frame(height: 29)
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
        .sheet(item: $evidenceService) { EvidenceView(service: $0) }
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
        .sheet(item: $aliasTarget) { target in
            AliasView(
                target: target,
                onSave: { alias in
                    store.assignAlias(alias, to: target.service) { result in
                        switch result {
                        case .success(let route): showMessage("Local address ready · \(route.alias).localhost")
                        case .failure(let error): showMessage(error.localizedDescription)
                        }
                    }
                },
                onRemove: target.service.route == nil ? nil : { alias in
                    store.removeAlias(alias) { result in
                        switch result {
                        case .success: showMessage("Local address removed")
                        case .failure(let error): showMessage(error.localizedDescription)
                        }
                    }
                }
            )
        }
        .task {
            let stored = UserDefaults.standard.stringArray(forKey: "expandedProjects") ?? []
            expanded = Set(stored)
            if store.document == nil { store.refresh() }
        }
        .onReceive(timer) { _ in store.refresh(silent: true) }
        .onChange(of: projects.map(\.id)) { _, ids in
            if !initializedExpansion {
                initializedExpansion = true
                if UserDefaults.standard.object(forKey: "expandedProjects") == nil {
                    expanded = Set(ids)
                }
            }
        }
        .onChange(of: expanded) { _, value in
            UserDefaults.standard.set(Array(value), forKey: "expandedProjects")
        }
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
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isOpen = searching || expanded.contains(project.id)
        let pageServices = project.services.filter(isOpenablePage)
        let relatedServices = project.services.filter { !isOpenablePage($0) }
        let pageApplications = project.applications.filter { $0.services.contains(where: isOpenablePage) }
        let relatedIsOpen = searching || expandedRelated.contains(project.id)
        let attention = project.services.filter {
            $0.listener.bindScope != "loopback" || $0.observation.classification == "suspected-web"
        }.count

        VStack(spacing: 0) {
            Button {
                guard !searching else { return }
                if isOpen { expanded.remove(project.id) } else { expanded.insert(project.id) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Circle()
                        .fill(attention > 0 ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(projectNames[project.id] ?? project.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                            Text(project.project?.branch ?? "No Git branch")
                            if let remote = compactRemote(project.project?.remoteUrl) {
                                Text("·")
                                Text(remote).lineLimit(1)
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 5)
                    Text(attention > 0 ? "\(attention) attention" : "\(pageServices.count) \(pageServices.count == 1 ? "app" : "apps")")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(attention > 0 ? Color.orange : Color.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background((attention > 0 ? Color.orange : Color.secondary).opacity(0.1), in: Capsule())
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Rename Project…", systemImage: "pencil") {
                    renameTarget = RenameTarget(
                        key: project.id,
                        kind: .project,
                        currentName: projectNames[project.id] ?? project.name
                    )
                }
            }

            if isOpen {
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
                            .padding(.leading, 42)
                            .padding(.trailing, 10)
                            .padding(.top, 5)
                        }
                        if !applicationPages.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(applicationPages) { service in
                                    ServiceRow(
                                        service: service,
                                        displayName: serviceNames[serviceRenameKey(service)] ?? serviceName(service),
                                        selected: selectedServiceID == service.id,
                                        onSelect: {
                                            selectedServiceID = selectedServiceID == service.id ? nil : service.id
                                        },
                                        onRename: {
                                            renameTarget = RenameTarget(
                                                key: serviceRenameKey(service),
                                                kind: .service,
                                                currentName: serviceNames[serviceRenameKey(service)] ?? serviceName(service)
                                            )
                                        },
                                        onAlias: { aliasTarget = AliasTarget(service: service) },
                                        onEvidence: { evidenceService = service },
                                        onMessage: showMessage
                                    )
                                    if service.id != applicationPages.last?.id { Divider() }
                                }
                            }
                            .padding(.leading, 32)
                        }
                    }

                    if !relatedServices.isEmpty {
                        Divider().padding(.leading, 32)
                        Button {
                            if relatedIsOpen { expandedRelated.remove(project.id) } else { expandedRelated.insert(project.id) }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .rotationEffect(.degrees(relatedIsOpen ? 90 : 0))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12)
                                Text("Related services")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Not a directly openable page")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text(String(relatedServices.count))
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.1), in: Capsule())
                            }
                            .contentShape(Rectangle())
                            .padding(.leading, 38)
                            .padding(.trailing, 12)
                            .frame(height: 34)
                        }
                        .buttonStyle(.plain)

                        if relatedIsOpen {
                            VStack(spacing: 0) {
                                ForEach(relatedServices) { service in
                                    RelatedServiceRow(service: service) { evidenceService = service }
                                    if service.id != relatedServices.last?.id { Divider() }
                                }
                            }
                            .padding(.leading, 44)
                        }
                    }
                }
            }
        }
    }

    private func quietCountRow(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(count))
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.1), in: Capsule())
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .frame(height: 36)
    }

    private func showMessage(_ value: String) {
        withAnimation { message = value }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { if message == value { message = nil } }
        }
    }
}

final class PortToolsAppDelegate: NSObject, NSApplicationDelegate {
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
