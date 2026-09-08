import AppKit
import Foundation

final class CoreRuntime: @unchecked Sendable {
    static let shared = CoreRuntime()

    private let lock = NSLock()
    private var process: Process?
    private var logHandle: FileHandle?
    private var activeInstanceToken: String?

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
            } catch CoreError.alreadyRunning {
                throw CoreError.alreadyRunning
            } catch {
                lastError = error
                if attempt < 7 { Thread.sleep(forTimeInterval: 0.35) }
            }
        }
        throw lastError
    }

    private func socketInstanceToken() -> String? {
        guard FileManager.default.fileExists(atPath: socketURL.path) else { return nil }
        let probe = Process()
        let output = Pipe()
        let errors = Pipe()
        probe.executableURL = executableURL
        probe.arguments = ["request", "--socket", socketURL.path, "--path", "/v1/health"]
        probe.standardOutput = output
        probe.standardError = errors
        do {
            try probe.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            probe.waitUntilExit()
            guard probe.terminationStatus == 0,
                  let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return document["instanceToken"] as? String
        } catch {
            return nil
        }
    }

    private func clearChild() {
        process = nil
        activeInstanceToken = nil
        try? logHandle?.close()
        logHandle = nil
    }

    private func startLocked() throws {
        if let process, process.isRunning {
            if let activeInstanceToken, socketInstanceToken() == activeInstanceToken { return }
            process.terminate()
            process.waitUntilExit()
            clearChild()
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CoreError.missingResource
        }
        if socketInstanceToken() != nil {
            throw CoreError.alreadyRunning
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
        let instanceToken = UUID().uuidString
        task.executableURL = executableURL
        task.arguments = [
            "serve",
            "--socket", socketURL.path,
            "--state", routeStateURL.path,
            "--proxy", ProcessInfo.processInfo.environment["PORT_TOOLS_PROXY_ADDRESS"] ?? "127.0.0.1:17890",
            "--parent-pid", String(ProcessInfo.processInfo.processIdentifier),
            "--instance-token", instanceToken,
        ]
        task.standardOutput = logHandle
        task.standardError = logHandle
        try task.run()
        process = task
        self.logHandle = logHandle

        for _ in 0..<80 {
            if !task.isRunning {
                clearChild()
                throw CoreError.failed("Port Tools core exited during startup. See \(logURL.path).")
            }
            if socketInstanceToken() == instanceToken {
                activeInstanceToken = instanceToken
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        task.terminate()
        task.waitUntilExit()
        clearChild()
        throw CoreError.failed("Port Tools core did not become ready.")
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        clearChild()
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
            "logicalServiceId": service.logicalId,
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

    func stopPlan(for service: ServiceRecord) throws -> StopPlanRecord {
        let data = try CoreRuntime.shared.request(method: "POST", path: "/v1/services/\(service.id)/stop-plan")
        return try JSONDecoder().decode(StopPlanRecord.self, from: data)
    }

    func gracefulStop(_ service: ServiceRecord, planToken: String) throws -> GracefulStopResult {
        let body = try JSONSerialization.data(withJSONObject: [
            "planToken": planToken,
            "timeoutSeconds": 5,
        ])
        let data = try CoreRuntime.shared.request(
            method: "POST",
            path: "/v1/services/\(service.id)/graceful-stop",
            body: body
        )
        return try JSONDecoder().decode(GracefulStopResult.self, from: data)
    }

    func updatePreferences(_ service: ServiceRecord, patch: [String: Any]) throws {
        let body = try JSONSerialization.data(withJSONObject: patch)
        _ = try CoreRuntime.shared.request(
            method: "PATCH",
            path: "/v1/services/\(service.logicalId)/preferences",
            body: body
        )
    }

    func forceStopPlan(_ service: ServiceRecord, gracefulAttemptToken: String) throws -> ForceStopPlanRecord {
        let body = try JSONSerialization.data(withJSONObject: ["gracefulAttemptToken": gracefulAttemptToken])
        let data = try CoreRuntime.shared.request(
            method: "POST", path: "/v1/services/\(service.id)/force-stop-plan", body: body
        )
        return try JSONDecoder().decode(ForceStopPlanRecord.self, from: data)
    }

    func forceStop(_ service: ServiceRecord, planToken: String) throws -> ForceStopResult {
        let body = try JSONSerialization.data(withJSONObject: ["planToken": planToken])
        let data = try CoreRuntime.shared.request(
            method: "POST", path: "/v1/services/\(service.id)/force-stop", body: body
        )
        return try JSONDecoder().decode(ForceStopResult.self, from: data)
    }
}
