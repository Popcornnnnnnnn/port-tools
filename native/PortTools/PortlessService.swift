import Combine
import Foundation
import ServiceManagement

enum PortlessRuntimeStatus: Equatable {
    case notRegistered
    case approvalRequired
    case checking
    case active
    case unavailable

    var message: String {
        switch self {
        case .notRegistered: return portToolsString("Port-free addresses are off. Addresses use :17890.")
        case .approvalRequired: return portToolsString("Approval is required in System Settings. Addresses use :17890 until approved.")
        case .checking: return portToolsString("Checking the port-free helper…")
        case .active: return portToolsString("Port-free addresses are active.")
        case .unavailable: return portToolsString("Port 80 is unavailable. Addresses use :17890.")
        }
    }
}

enum PortlessHelperProbe {
    case healthy
    /// Nothing answers on port 80, so the registered daemon never started.
    case noListener
    /// Something answers but it is not the helper, so the port is taken.
    case unavailable
}

private func probePortlessHelper() async -> PortlessHelperProbe {
    guard let url = URL(string: "http://port-tools.localhost/__port_tools/health") else { return .unavailable }
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 1.5
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .unavailable }
        return object["service"] as? String == "port-tools-portless-helper"
            && object["status"] as? String == "ok"
            ? .healthy
            : .unavailable
    } catch let error as URLError {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
            return .noListener
        default:
            return .unavailable
        }
    } catch {
        return .unavailable
    }
}

@MainActor
final class PortlessServiceController: ObservableObject {
    static let shared = PortlessServiceController()
    static let plistName = "PortlessHelper.plist"

    @Published private(set) var runtimeStatus: PortlessRuntimeStatus = .notRegistered
    @Published private(set) var lastError: String?
    private var refreshGeneration = 0
    private var registrationRefreshInProgress = false
    private var repairedDeadRegistration = false
    private var registrationRecoveryAttempted = false
    private let publicPortQueue = DispatchQueue(label: "xyz.popcornnn.PortTools.public-port")
    private let registeredHelperRevisionKey = "portlessHelperRegisteredRevision"
    private let legacyRegisteredBuildKey = "portlessHelperRegisteredBuild"

    private var isDisabledForTests: Bool {
        ProcessInfo.processInfo.environment["PORT_TOOLS_DISABLE_PORTLESS"] == "1"
    }

    private var service: SMAppService {
        SMAppService.daemon(plistName: Self.plistName)
    }

    var isRegistered: Bool {
        if isDisabledForTests { return false }
        switch service.status {
        case .enabled, .requiresApproval: return true
        case .notRegistered, .notFound: return false
        @unknown default: return false
        }
    }

    private var currentHelperRevision: String {
        Bundle.main.object(forInfoDictionaryKey: "PortlessHelperRevision") as? String ?? "1"
    }

    private var hasRegistrationIntent: Bool {
        UserDefaults.standard.string(forKey: registeredHelperRevisionKey) != nil
            || UserDefaults.standard.string(forKey: legacyRegisteredBuildKey) != nil
    }

    private func rememberCurrentHelperRevision() {
        UserDefaults.standard.set(currentHelperRevision, forKey: registeredHelperRevisionKey)
        UserDefaults.standard.removeObject(forKey: legacyRegisteredBuildKey)
    }

    func refreshRouting() {
        if isDisabledForTests {
            runtimeStatus = .notRegistered
            useFallbackRouting()
            return
        }
        recoverPreviousRegistrationIfNeeded()
        if refreshRegistrationIfNeeded() { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        lastError = nil
        switch service.status {
        case .notRegistered, .notFound:
            runtimeStatus = .notRegistered
            useFallbackRouting()
        case .requiresApproval:
            runtimeStatus = .approvalRequired
            useFallbackRouting()
        case .enabled:
            runtimeStatus = .checking
            Task {
                let probe = await probePortlessHelper()
                guard generation == refreshGeneration else { return }
                // launchd reports the helper as enabled but nothing listens on
                // port 80: the registration points at a bundle that no longer
                // exists, so register it again against the current bundle.
                if probe == .noListener, !repairedDeadRegistration {
                    repairedDeadRegistration = true
                    if reRegisterHelper() { return }
                }
                let available = probe == .healthy
                let error = await applyPublicPort(available ? 80 : 0)
                guard generation == refreshGeneration else { return }
                if let error {
                    runtimeStatus = .unavailable
                    lastError = error.localizedDescription
                    useFallbackRouting()
                } else {
                    runtimeStatus = available ? .active : .unavailable
                }
            }
        @unknown default:
            runtimeStatus = .unavailable
            useFallbackRouting()
        }
    }

    func enable() {
        guard !isDisabledForTests else { return }
        lastError = nil
        do {
            if service.status == .notRegistered || service.status == .notFound {
                try service.register()
            }
        } catch {
            if service.status != .requiresApproval {
                lastError = error.localizedDescription
            }
        }
        if service.status == .requiresApproval {
            rememberCurrentHelperRevision()
            runtimeStatus = .approvalRequired
            useFallbackRouting()
            SMAppService.openSystemSettingsLoginItems()
        } else {
            if service.status == .enabled {
                rememberCurrentHelperRevision()
            }
            refreshRouting()
        }
    }

    func disable() {
        guard !isDisabledForTests else { return }
        refreshGeneration += 1
        lastError = nil
        do {
            if service.status != .notRegistered && service.status != .notFound {
                try service.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        runtimeStatus = .notRegistered
        UserDefaults.standard.removeObject(forKey: registeredHelperRevisionKey)
        UserDefaults.standard.removeObject(forKey: legacyRegisteredBuildKey)
        useFallbackRouting()
    }

    private func recoverPreviousRegistrationIfNeeded() {
        guard hasRegistrationIntent,
              service.status == .notRegistered || service.status == .notFound
        else { return }
        guard !registrationRecoveryAttempted else { return }
        registrationRecoveryAttempted = true
        // Background Task Management can keep a record of the helper after an
        // app update while launchd has no job behind it. register() then finds
        // the existing record and never creates the job, so clear it first.
        service.unregister { _ in
            Task { @MainActor in
                do {
                    try self.service.register()
                    self.rememberCurrentHelperRevision()
                } catch {
                    NSLog("Port Tools portless: register failed: %@", error.localizedDescription)
                    if self.service.status != .requiresApproval {
                        self.lastError = error.localizedDescription
                    }
                }
                self.refreshRouting()
            }
        }
    }

    private func refreshRegistrationIfNeeded() -> Bool {
        let status = service.status
        guard status == .enabled || status == .requiresApproval else { return false }
        guard let registeredRevision = UserDefaults.standard.string(forKey: registeredHelperRevisionKey) else {
            rememberCurrentHelperRevision()
            return false
        }
        guard registeredRevision != currentHelperRevision else { return false }
        return reRegisterHelper()
    }

    private func reRegisterHelper() -> Bool {
        guard !registrationRefreshInProgress else { return true }
        registrationRefreshInProgress = true
        runtimeStatus = .checking
        useFallbackRouting()
        service.unregister { error in
            Task { @MainActor in
                self.registrationRefreshInProgress = false
                if let error {
                    self.runtimeStatus = .unavailable
                    self.lastError = error.localizedDescription
                    return
                }
                do {
                    try self.service.register()
                    self.rememberCurrentHelperRevision()
                    self.refreshRouting()
                } catch {
                    self.runtimeStatus = self.service.status == .requiresApproval ? .approvalRequired : .unavailable
                    self.lastError = error.localizedDescription
                    if self.service.status == .requiresApproval {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }
        }
        return true
    }

    private func useFallbackRouting() {
        Task { [weak self] in
            guard let self else { return }
            if let error = await self.applyPublicPort(0) {
                self.lastError = error.localizedDescription
            }
        }
    }

    /// Every core call spawns the bundled helper process and waits for it, so
    /// these writes run on a serial queue instead of the main thread. The queue
    /// keeps the last requested port authoritative when activations overlap.
    private func applyPublicPort(_ port: Int) async -> Error? {
        await withCheckedContinuation { continuation in
            publicPortQueue.async {
                let result: Error?
                do {
                    try CoreRuntime.shared.setPublicPort(port)
                    result = nil
                } catch {
                    result = error
                }
                continuation.resume(returning: result)
            }
        }
    }
}
