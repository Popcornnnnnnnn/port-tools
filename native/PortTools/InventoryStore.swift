import Combine
import Foundation

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

    func stopPlan(for service: ServiceRecord, completion: @escaping (Result<StopPlanRecord, Error>) -> Void) {
        let provider = provider
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try provider.stopPlan(for: service) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func gracefulStop(
        _ service: ServiceRecord,
        planToken: String,
        completion: @escaping (Result<GracefulStopResult, Error>) -> Void
    ) {
        let provider = provider
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try provider.gracefulStop(service, planToken: planToken) }
            DispatchQueue.main.async {
                completion(result)
                if case .success = result { self.refresh() }
            }
        }
    }

    func updatePreferences(
        _ service: ServiceRecord,
        patch: [String: Any],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let provider = provider
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try provider.updatePreferences(service, patch: patch) }
            DispatchQueue.main.async {
                completion(result)
                if case .success = result { self.refresh() }
            }
        }
    }

    func forceStopPlan(
        _ service: ServiceRecord,
        gracefulAttemptToken: String,
        completion: @escaping (Result<ForceStopPlanRecord, Error>) -> Void
    ) {
        let provider = provider
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try provider.forceStopPlan(service, gracefulAttemptToken: gracefulAttemptToken) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func forceStop(
        _ service: ServiceRecord,
        planToken: String,
        completion: @escaping (Result<ForceStopResult, Error>) -> Void
    ) {
        let provider = provider
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try provider.forceStop(service, planToken: planToken) }
            DispatchQueue.main.async {
                completion(result)
                if case .success = result { self.refresh() }
            }
        }
    }
}
