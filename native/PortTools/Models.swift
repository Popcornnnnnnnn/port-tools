import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

struct ListenerRecord: Codable, Sendable {
    let address: String
    let port: Int
    let bindScope: String
}
struct ProcessRecord: Codable, Sendable {
    let pid: Int
    let parentPid: Int?
    let owner: String?
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
    let contentType: String?
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
    let lastResolvedPort: Int?
    let logicalServiceId: String?
}

struct ServiceHistoryRecord: Codable, Sendable {
    let firstSeen: String
    let lastSeen: String
    let lastSuccessfulProbe: String?
    let firstFailedProbe: String?
    let consecutiveProbeFailures: Int
    let initialParentPid: Int?
}

struct ServicePreferencesRecord: Codable, Sendable {
    let displayName: String?
    let pinned: Bool
    let ignored: Bool
    let classificationOverride: String?
}

struct StalenessRecord: Codable, Sendable {
    let possiblyForgotten: Bool
    let reasons: [String]
}

struct ServiceRecord: Codable, Identifiable, Sendable {
    let id: String
    let logicalId: String
    let listener: ListenerRecord
    let process: ProcessRecord
    let project: ProjectRecord?
    let application: ApplicationRecord?
    let observation: ObservationRecord
    let relevance: RelevanceRecord
    let history: ServiceHistoryRecord
    let preferences: ServicePreferencesRecord
    let staleness: StalenessRecord
    let route: RouteRecord?
}

struct ScanDocument: Codable, Sendable {
    let generatedAt: String
    let services: [ServiceRecord]
}

struct StopProcessRecord: Codable, Sendable {
    let pid: Int
    let name: String?
    let owner: String?
    let command: String?
    let projectRoot: String?
    let applicationRoot: String?
    let reason: String?
}

struct StopListenerTarget: Codable, Sendable {
    let pid: Int
    let address: String
    let port: Int
    let currentPids: [Int]?
}

struct GracefulStopPlan: Codable, Sendable {
    let signal: String
    let pids: [Int]
    let verifyListenersReleased: [StopListenerTarget]
}

struct StopPlanRecord: Codable, Sendable {
    let decision: String
    let reasons: [String]
    let rootProcess: StopProcessRecord
    let descendants: [StopProcessRecord]
    let exclusions: [StopProcessRecord]
    let gracefulPlan: GracefulStopPlan
    let planToken: String?
    let expiresAt: String?
}

struct GracefulStopResult: Codable, Sendable {
    let decision: String
    let reasons: [String]
    let signalSent: Bool
    let signaledPids: [Int]
    let listenersReleased: Bool
    let forceStopPerformed: Bool
    let success: Bool
    let forceStopAvailable: Bool
    let gracefulAttemptToken: String?
    let remainingListeners: [StopListenerTarget]
}

struct ForceStopPlanRecord: Codable, Sendable {
    let decision: String
    let reasons: [String]
    let processes: [StopProcessRecord]
    let verifyListenersReleased: [StopListenerTarget]
    let requiresSecondConfirmation: Bool
    let planToken: String?
    let expiresAt: String?
}

struct ForceStopResult: Codable, Sendable {
    let decision: String
    let reasons: [String]
    let signalSent: Bool
    let signaledPids: [Int]
    let listenersReleased: Bool
    let remainingListeners: [StopListenerTarget]
    let forceStopPerformed: Bool
    let success: Bool
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
    case alreadyRunning
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "Bundled Port Tools core is missing."
        case .alreadyRunning:
            return "Another Port Tools instance is already running."
        case .failed(let message):
            return message
        }
    }
}

protocol InventoryProviding: Sendable {
    func scan() throws -> ScanDocument
    func assignAlias(_ alias: String, to service: ServiceRecord) throws -> RouteRecord
    func removeAlias(_ alias: String) throws
    func stopPlan(for service: ServiceRecord) throws -> StopPlanRecord
    func gracefulStop(_ service: ServiceRecord, planToken: String) throws -> GracefulStopResult
    func updatePreferences(_ service: ServiceRecord, patch: [String: Any]) throws
    func forceStopPlan(_ service: ServiceRecord, gracefulAttemptToken: String) throws -> ForceStopPlanRecord
    func forceStop(_ service: ServiceRecord, planToken: String) throws -> ForceStopResult
}
