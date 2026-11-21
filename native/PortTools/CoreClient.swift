import AppKit
import Darwin
import Foundation

private enum UnixSocketHTTPClient {
    enum TransportError: Error {
        case invalidPath
        case socketFailed(Int32)
        case connectFailed(Int32)
        case writeFailed(Int32)
        case readFailed(Int32)
        case malformedResponse
    }

    static func send(
        socketPath: String,
        method: String,
        path: String,
        body: Data?,
        timeoutSeconds: Int
    ) throws -> (statusCode: Int, body: Data) {
        var addr = sockaddr_un()
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8CString)
        let sunPathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= sunPathCapacity else {
            throw TransportError.invalidPath
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            sunPathPtr.withMemoryRebound(to: CChar.self, capacity: sunPathCapacity) { destination in
                for (index, byte) in pathBytes.enumerated() {
                    destination[index] = byte
                }
            }
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw TransportError.socketFailed(errno)
        }
        defer { Darwin.close(fd) }

        var noSigPipe: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let connectResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                Darwin.connect(fd, sockAddr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw TransportError.connectFailed(errno)
        }

        var header = "\(method) \(path) HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n"
        if let body {
            header += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
        }
        header += "\r\n"
        var requestData = Data(header.utf8)
        if let body {
            requestData.append(body)
        }

        try requestData.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < rawBuffer.count {
                let written = Darwin.send(fd, base.advanced(by: sent), rawBuffer.count - sent, 0)
                if written > 0 {
                    sent += written
                } else if written < 0 && errno == EINTR {
                    continue
                } else {
                    throw TransportError.writeFailed(errno)
                }
            }
        }

        var rawResponse = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let readCount = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.recv(fd, rawBuffer.baseAddress!, rawBuffer.count, 0)
            }
            if readCount > 0 {
                rawResponse.append(buffer, count: readCount)
            } else if readCount == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                throw TransportError.readFailed(errno)
            }
        }

        let separator = Data("\r\n\r\n".utf8)
        guard let boundary = rawResponse.range(of: separator) else {
            throw TransportError.malformedResponse
        }
        let headerData = rawResponse[..<boundary.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw TransportError.malformedResponse
        }
        let headerLines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = headerLines.first else {
            throw TransportError.malformedResponse
        }
        let statusParts = statusLine.split(separator: " ")
        guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
            throw TransportError.malformedResponse
        }

        var responseBody = Data(rawResponse[boundary.upperBound...])
        let isChunked = headerLines.dropFirst().contains { line in
            let lower = line.lowercased()
            return lower.hasPrefix("transfer-encoding:") && lower.contains("chunked")
        }
        if isChunked {
            responseBody = try decodeChunkedBody(responseBody)
        }
        return (statusCode, responseBody)
    }

    private static func decodeChunkedBody(_ data: Data) throws -> Data {
        var decoded = Data()
        var index = data.startIndex
        let crlf = Data("\r\n".utf8)
        while index < data.endIndex {
            guard let lineEnd = data.range(of: crlf, in: index..<data.endIndex) else {
                throw TransportError.malformedResponse
            }
            guard let sizeLine = String(data: data[index..<lineEnd.lowerBound], encoding: .ascii) else {
                throw TransportError.malformedResponse
            }
            let sizeHex = sizeLine.split(separator: ";", maxSplits: 1)[0].trimmingCharacters(in: .whitespaces)
            guard let chunkSize = Int(sizeHex, radix: 16) else {
                throw TransportError.malformedResponse
            }
            index = lineEnd.upperBound
            if chunkSize == 0 {
                return decoded
            }
            guard let chunkEnd = data.index(index, offsetBy: chunkSize, limitedBy: data.endIndex),
                  let trailerEnd = data.index(chunkEnd, offsetBy: 2, limitedBy: data.endIndex)
            else {
                throw TransportError.malformedResponse
            }
            decoded.append(data[index..<chunkEnd])
            index = trailerEnd
        }
        return decoded
    }
}

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
        do {
            let response = try UnixSocketHTTPClient.send(
                socketPath: socketURL.path, method: "GET", path: "/v1/health", body: nil, timeoutSeconds: 2
            )
            guard response.statusCode == 200,
                  let document = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
            else { return nil }
            return document["instanceToken"] as? String
        } catch {
            return nil
        }
    }

    private func rotateLogIfNeeded() {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.int64Value > 1_048_576
        else { return }
        let rotatedURL = logURL.appendingPathExtension("1")
        try? fileManager.removeItem(at: rotatedURL)
        try? fileManager.moveItem(at: logURL, to: rotatedURL)
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
        rotateLogIfNeeded()
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
        let needsStart: Bool = {
            lock.lock()
            defer { lock.unlock() }
            return !(process?.isRunning == true && activeInstanceToken != nil)
        }()
        if needsStart {
            try start()
        }

        let socketPath = socketURL.path
        let response: (statusCode: Int, body: Data)
        do {
            response = try UnixSocketHTTPClient.send(
                socketPath: socketPath, method: method, path: path, body: body, timeoutSeconds: 15
            )
        } catch is UnixSocketHTTPClient.TransportError {
            try start()
            response = try UnixSocketHTTPClient.send(
                socketPath: socketPath, method: method, path: path, body: body, timeoutSeconds: 15
            )
        }

        guard (200..<300).contains(response.statusCode) else {
            let apiMessage = (try? JSONSerialization.jsonObject(with: response.body))
                .flatMap { $0 as? [String: Any] }?["error"] as? String
            throw CoreError.failed(apiMessage ?? "Port Tools core request failed (\(response.statusCode)).")
        }
        return response.body
    }

    func setPublicPort(_ port: Int) throws {
        let body = try JSONSerialization.data(withJSONObject: ["port": port])
        _ = try request(method: "PUT", path: "/v1/settings/public-port", body: body)
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
